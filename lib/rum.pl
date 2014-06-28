use strict;
use warnings;
use Rum;
use Rum::Module;
use Carp;
use Data::Dumper;
use Rum::Wrap::TTY;
use Rum::Net::Socket;
use Rum::Loop::Utils 'assert';
my $_errorHandler;
my $assert;

sub Rum::Process::startup {
    
    #do this good and early, since it handles errors.
    processFatal();
    
    ## those already set in Rum.pm =================
    #globalVariables();
    #globalTimeouts();
    #globalConsole();
    #===============================================
    
    processAssert();
    # NOTHING TODO - processConfig();
    processStdio();
    processKillAndExit();
    processSignalHandlers();
    processChannel();
    processRawDebug();
    resolveArgv0();
    
    my $argv = process->argv;
    ###process argument
    if ($argv->[1] eq 'debug') {
        #Start the debugger agent
        #var d = NativeModule.require('_debugger');
        #d.start();
    } elsif (process->{_eval}) {
        #User passed '-e' or '--eval' arguments to Node.
        evalScript('[eval]');
    } elsif ($argv->[1]) {
        #make process->argv->[1] into a full path
        my $path = Require('path');
        process->argv->[1] = $path->resolve($argv->[1]);
        
        #If this is a worker in cluster mode, start up the communication
        #channel.
        if (process->env->{RUM_UNIQUE_ID}) {
            my $cluster = Require('cluster');
            $cluster->_setupWorker();
            
            #Make sure it's not accidentally inherited by child processes.
            delete process->env->{RUM_UNIQUE_ID};
        }
        
        ##main entry point
        Require($argv->[1]);
        
    } else {
        #TODO -- repl
    }
}

sub processFatal {
    *Rum::Process::_fatalException = sub {
        
    };
}

sub processAssert {
    *Rum::Process::assert = $assert = sub  {
        my ($this, $x, $msg) = @_;
        Carp::croak($msg || 'assertion error') if !$x;
    };
}

sub processStdio {
    
    my ($stdin, $stdout, $stderr);
    *Rum::Process::stdout = sub {
        if ($stdout) { return $stdout };
        
        $stdout = createWritableStdioStream(*STDOUT);
        return $stdout;
        
    };
    
    
    *Rum::Process::stderr = sub {
        if ($stderr) { return $stderr };
        $stderr = createWritableStdioStream(*STDERR);
        return $stderr;
    };
    
    use Data::Dumper;
    *Rum::Process::stdin = sub {
        if ($stdin) { return $stdin };
        
        my $switch = Rum::Wrap::TTY::guessHandleType(*STDIN);
        my $fd = fileno *STDIN;
        
        if ($switch eq 'TTY') {
            
        } elsif ($switch eq 'FILE'){
            
        } elsif ($switch eq 'TCP' || $switch eq 'PIPE'){
            $stdin = Rum::Net::Socket->new({
                fd => $fd,
                fh => *STDIN,
                readable => 1,
                writable => 0
            });
        } else {
            die ('Implement me. Unknown stdin file type!');
        }
        
        return $stdin;
    };
    
    *Rum::Process::openStdin = sub {
        process->stdin->resume();
        return Rum::Process::stdin();
    };
    
}

sub createWritableStdioStream {
    my $fh = shift;
    
    my $stream;
    #my $tty_wrap = Require('net');
    
    my $type = Rum::Wrap::TTY::guessHandleType($fh);
    if ($type eq 'TTY') {
        my $tty = Require('tty');
        $stream = $tty->WriteStream->new($fh);
        $stream->{_type} = 'tty';
        
        if ( $stream->{_handle} && $stream->{_handle}->can('unref') ) {
            $stream->{_handle}->unref();
        }
        
    } elsif ($type eq 'FILE'){
        die "FILE TYPE";
    } elsif ($type eq 'TCP' || $type eq 'PIPE'){
        
        $stream = Rum::Net::Socket->new({
            fh => $fh,
            fd => fileno $fh,
            readable => 0,
            writable => 1
        });
    }
    return $stream;
}


sub processKillAndExit {}
sub processSignalHandlers {}
sub processChannel {
    
    #If we were spawned with env NODE_CHANNEL_FD then load that up and
    #start parsing data from that stream.
    if (process->{env}->{NODE_CHANNEL_FD}) {
        
        my $fd = process->{env}->{NODE_CHANNEL_FD};
        assert($fd >= 0);
        #Make sure it's not accidentally inherited by child processes.
        delete process->{env}->{NODE_CHANNEL_FD};
        
        my $cp = Require('child_process');
        
        #Load tcp_wrap to avoid situation where we might immediately receive
        #a message.
        #FIXME is this really necessary?
        #process.binding('tcp_wrap');
        
        $cp->_forkChild($fd);
        #assert(process.send);
    }
}

sub processRawDebug {}

sub evalScript {
    my $name = shift;
    my $path = Require('path');
    my $cwd = process->cwd();
    my $module = Rum::Module->new($name);
    my $filename = $module->{filename} = $path->join($cwd,$name);
    my $script = process->{_eval};
    local $@;
    my $ret = eval qq{
        package Rum::SandBox::Eval {
            use Rum;
            {
                no warnings 'redefine';
                sub __dirname {'.'}
                sub __filename {\$filename}
                sub Require { Rum::Module::Require(shift,\$module) }
                sub exports  { \$module->{exports} }
                sub module { \$module }
            }
            eval { $script };
        }
    };
    
    if ($@) {
        print STDERR $@;
        exit(1);
    }
    
    #var result = module._compile(script, name + '-wrapper');
    if (process->{_print_eval}){
        print $ret || '' . "\n";
    }
}

sub resolveArgv0 {
    my $cwd = process->cwd();
    my $isWindows = process->platform eq 'win32';
    
    my $arg = process->argv->[0];
    
    if (!$isWindows && index($arg,'/') != -1  && substr($arg, 0, 1) ne '/') {
        my $path = Require('path');
        process->argv->[0] = $path->join($cwd,process->argv->[0]);
    }
}

# 1 - processNextTick
# 2 - TODO - processAsyncListener();
# 3 - TODO - processKillAndExit();
package Rum::Process; {
    use Rum::TryCatch;
    sub process { &Rum::process }
    
    my $asyncFlags = {
        kCount => 0
    };
    
    my $nextTickQueue = [];
    my $_runAsyncQueue = process->{_runAsyncQueue};
    my $_loadAsyncQueue = process->{_loadAsyncQueue};
    my $_unloadAsyncQueue = process->{_unloadAsyncQueue};
    
    #This tickInfo thing is used so that the C++ code in src/node.cc
    #can have easy accesss to our nextTick state, and avoid unnecessary
    my $tickInfo = {
        kInTick => 0,
        kIndex => 0,
        kLastThrew => 0,
        kLength => 0
    };
    
    process->_setupNextTick($tickInfo, \&_tickCallback);
    
    sub tickDone {
        if ($tickInfo->{kLength} != 0) {
            if ($tickInfo->{kLength} <= $tickInfo->{kIndex}) {
                $nextTickQueue = [];
                $tickInfo->{kLength} = 0;
            } else {
                splice @{$nextTickQueue}, 0, $tickInfo->{kIndex};
                $tickInfo->{kLength} = scalar @{$nextTickQueue};
            }
        }
        $tickInfo->{kIndex} = 0;
    }
    
    #Run callbacks that have no domain.
    sub _tickCallback {
        my ($callback, $hasQueue, $threw, $tock);
        while ($tickInfo->{kIndex} < $tickInfo->{kLength}) {
            $tock = $nextTickQueue->[$tickInfo->{kIndex}++];
            $callback = $tock->{callback};
            $threw = 1;
            $hasQueue = !!$tock->{_asyncQueue};
            if ($hasQueue) {
                _loadAsyncQueue($tock);
            }
            
            try {
                $callback->();
                $threw = 0;
            } finally {
                if ($threw) {
                    tickDone();
                    my $er = @_;
                    die @_;
                }
            };
            
            if ($hasQueue) {
                _unloadAsyncQueue($tock);
            }
        }   
        tickDone();
    }
    
    sub tick_info { $tickInfo }
    
    sub nextTick {
        
        my ($s,$callback) = @_;
        
        #on the way out, don't bother. it won't get fired anyway.
        return if process->{_exiting};
        
        my $obj = {
            callback => $callback,
            _asyncQueue => undef
        };
        
        if ($asyncFlags->{kCount} > 0){
            $_runAsyncQueue->($obj);
        }
        
        push @{$nextTickQueue},$obj;
        $tickInfo->{kLength}++;
    }    
};

return \&startup;

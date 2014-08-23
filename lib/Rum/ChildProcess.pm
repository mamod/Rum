package Rum::ChildProcess;
use strict;
use warnings;
use Rum 'process';
use Rum::Utils;
use Rum::Wrap::Process;
use Rum::Wrap::Pipe;
use Rum::Loop::Flags ':Platform';
use Rum::Loop::Signal ();
use Rum::StringDecoder;
use Rum::Error;
use Rum::Buffer;
use Rum::Loop::Utils 'assert';
use base 'Rum::Events';
use POSIX  qw[:errno_h];
use Rum::Net::Socket;

use Data::Dumper;
my $util = 'Rum::Utils';

sub errnoException {&Rum::Utils::_errnoException}

sub new {
    
    my $this = bless {}, shift;
    Rum::Events::new($this);
    my $self = $this;
    
    $this->{_closesNeeded} = 1;
    $this->{_closesGot} = 0;
    $this->{connected} = 0;
    
    $this->{signalCode} = undef;
    $this->{exitCode} = undef;
    $this->{killed} = 0;
    
    $this->{_handle} = Rum::Wrap::Process->new();
    $this->{_handle}->{owner} = $this;
    
    $this->{_handle}->{onexit} = sub {
        my ($exitCode, $signalCode) = @_;
        #follow 0.4.x behaviour:
        #- normally terminated processes don't touch this.signalCode
        #- signaled processes don't touch this.exitCode
        #new in 0.9.x:
        #- spawn failures are reported with exitCode < 0
        my $err = ($exitCode < 0) ? errnoException($exitCode, 'spawn') : undef;
        
        if ($signalCode) {
            $self->{signalCode} = $signalCode;
        } else {
            $self->{exitCode} = $exitCode;
        }
        
        if ($self->{stdin}) {
            $self->{stdin}->destroy();
        }
        
        $self->{_handle}->close();
        undef $self->{_handle};
        
        if ($exitCode == 255) {
            #die $@;
        }
        
        if ($exitCode < 0) {
            $self->emit('error', $err);
        } else {
            $self->emit('exit', $self->{exitCode}, $self->{signalCode});
        }
        
        #if any of the stdio streams have not been touched,
        # then pull all the data through so that it can get the
        # eof and emit a 'close' event.
        # Do it on nextTick so that the user has one last chance
        # to consume the output, if for example they only want to
        # start reading the data once the process exits.
        process->nextTick(sub {
            flushStdio($self);
        });
        
        maybeClose($self);
    };
    
    return $this;
}

sub maybeClose {
    my $subprocess = shift;
    $subprocess->{_closesGot}++;
    $subprocess->{_closesNeeded} ||= 1;
    if ( $subprocess->{_closesGot} == $subprocess->{_closesNeeded} ) {
        $subprocess->emit('close', $subprocess->{exitCode}, $subprocess->{signalCode});
    }
}

sub flushStdio {
    my $subprocess = shift;
    my $stdio = $subprocess->{stdio};
    foreach my $stream (@{$stdio}) {
        if (!$stream || !$stream->{readable} || $stream->{_consuming} ||
            $stream->{_readableState}->{flowing} ) {
            next;
        }
        
        $stream->resume();
    }
}

sub spawn {
    my $self = shift;
    my $options = shift;
    my ($ipc,$ipcFd);
    my $this = $self;
    
    #If no `stdio` option was given - use default
    my $stdio = $options->{stdio} || 'pipe';
    $stdio = _validateStdio($stdio, 0);
    
    $ipc = $stdio->{ipc};
    $ipcFd = $stdio->{ipcFd};
    $stdio = $options->{stdio} = $stdio->{stdio};
    if (!$util->isUndefined($ipc)) {
        #Let child process know about opened IPC channel
        $options->{envPairs} ||= {};
        $options->{envPairs}->{NODE_CHANNEL_FD} = $ipcFd;
    }
    
    my $err = $this->{_handle}->spawn($options);
    my $childpid = $this->{_handle}->{pid};
    if ($err == ENOENT) {
        process->nextTick(sub {
            my $error = $err+0;
            $error = -$error;
            $self->{_handle}->{onexit}->($error);
        });
    } elsif ($err) {
        #Close all opened fds on error
        foreach my $std (@{$stdio}){
            if ($std->{type} eq 'pipe') {
                $std->{handle}->close();
            }
            
        }
        
        $this->{_handle}->close();
        undef $this->{_handle};
        errnoException($err, 'spawn')->throw();
    }
    
    $this->{pid} = $this->{_handle}->{pid};
    
    my $i = -1;
    foreach my $std (@{$stdio}){
        $i++;
        if ( $std->{type} eq 'ignore' ) {
            next;
        }
        
        if ( $std->{ipc} ) {
            $self->{_closesNeeded}++;
            next;
        }
        
        if ( $std->{handle} ) {
            #when i === 0 - we're dealing with stdin
            #(which is the only one writable pipe)
            $std->{socket} = createSocket($self->{pid} && $self->{pid} != 0 ?
                                          $std->{handle} : undef, $i > 0);
            if ($i > 0 && $self->{pid} && $self->{pid} != 0) {
                $self->{_closesNeeded}++;
                $std->{socket}->on('close', sub {
                    maybeClose($self);
                });
            }
        }
    }
    
    $this->{stdin} = scalar @{$stdio} >= 1 &&
        !$util->isUndefined($stdio->[0]->{socket}) ?
        $stdio->[0]->{socket} : undef;
    
    $this->{stdout} = scalar @{$stdio} >= 2 &&
        !$util->isUndefined($stdio->[1]->{socket}) ?
        $stdio->[1]->{socket} : undef;
    
    $this->{stderr} = scalar @{$stdio} >= 3 &&
        !$util->isUndefined($stdio->[2]->{socket}) ?
        $stdio->[2]->{socket} : undef;
    
    my $x = 0;
    $this->{stdio} = [];
    foreach my $std (@{$stdio}){
        if (!$std->{socket}) {
            $this->{stdio}->[$x] = undef;
        } else {
            $this->{stdio}->[$x] = $std->{socket};
        }
        $x++;
    }
    
    ##Add .send() method and start listening for IPC data
    if ($ipc) { setupChannel($this, $ipc) };
    #return $err;
}

sub ref {
    my $this = shift;
    if ($this->{_handle}) { $this->{_handle}->ref() };
}

sub unref {
    my $this = shift;
    if ($this->{_handle}) { $this->{_handle}->unref() };
}

sub stdout {
    my $this = shift;
    return $this->{stdout};
}

sub stdin {
    my $this = shift;
    return $this->{stdin};
}

sub stderr {
    my $this = shift;
    return $this->{stderr};
}

#constructors for lazy loading
sub createPipe {
    my $ipc = shift;
    return Rum::Wrap::Pipe->new($ipc);
}

sub createSocket {
    my ($pipe, $readable) = @_;
    my $s = Rum::Net::Socket->new({ handle => $pipe });
    if ($readable) {
        $s->{writable} = 0;
        $s->{readable} = 1;
    } else {
        $s->{writable} = 1;
        $s->{readable} = 0;
    }
    return $s;
}

sub _validateStdio {
    my ($stdio, $sync) = @_;
    my ($ipc,$ipcFd);
    
    #Replace shortcut with an array
    if ($util->isString($stdio)) {
        if ($stdio eq 'ignore') {
            $stdio = ['ignore', 'ignore', 'ignore'];
        } elsif ($stdio eq 'pipe') {
            $stdio = ['pipe', 'pipe', 'pipe'];
        } elsif ($stdio eq 'inherit'){
            $stdio = [0, 1, 2];
        } else {
            die 'Incorrect value of stdio option: ' . $stdio;
        }
    } elsif (!$util->isArray($stdio)) {
        die ('Incorrect value of stdio option: ' .
            $util->inspect($stdio));
    }
    
    while (scalar @{$stdio} < 3) { push @{$stdio} , undef };
    
    #Translate stdio into Rum::Loop readable form
    #(i.e. PipeWraps or fds)
    $stdio = $util->reduce($stdio, sub {
        my ($acc, $stdio, $i) = @_;
        my $cleanup = sub {
            my $new = $util->filter($acc, sub {
                my $stdio = shift;
                return $stdio->{type} eq 'pipe' || $stdio->{type} eq 'ipc';
            });
            
            foreach my $std (@{$new}){
                if ($std->{handle}){
                    $std->{handle}->close();
                }
            }
        };
        
        #Defaults
        if ($util->isNullOrUndefined($stdio)) {
            $stdio = $i < 3 ? 'pipe' : 'ignore';
        }
        
        if (!defined $stdio || $stdio eq 'ignore') {
            push @{$acc}, {type => 'ignore'};
        } elsif ($stdio eq 'pipe' || $util->isNumber($stdio) && $stdio < 0) {
            my $a = {
                type => 'pipe',
                readable => $i == 0,
                writable => $i != 0
            };
            
            if (!$sync){
                $a->{handle} = createPipe();
            }
            push @{$acc}, $a;
            
        } elsif ( $stdio eq 'ipc' ) {
            if ($sync || !$util->isUndefined($ipc)) {
                #Cleanup previously created pipes
                $cleanup->();
                if (!$sync){
                    die('Child process can have only one IPC pipe');
                } else {
                    die('You cannot use IPC with synchronous forks');
                }
            }
            
            $ipc = createPipe(1);
            $ipcFd = $i;
            push @{$acc}, {
                type => 'pipe',
                handle => $ipc,
                ipc => 1
            };
            
        } elsif ($stdio eq 'inherit') {
            push @{$acc}, {
                type => 'inherit',
                fd => $i
            };
        } elsif ( $util->isNumber($stdio) || $util->isNumber($stdio->{fd}) ) {
            push @{$acc}, {
                type => 'fd',
                fd => CORE::ref $stdio ? $stdio->{fd} : $stdio
            };
            
        } elsif (getHandleWrapType($stdio) || getHandleWrapType($stdio->{handle}) ||
                getHandleWrapType($stdio->{_handle})) {
            
            my $handle = getHandleWrapType($stdio) ? $stdio : 
            				getHandleWrapType($stdio->{handle}) ? 
            					$stdio->{handle} : $stdio->{_handle};
            
            push @{$acc}, {
                type => 'wrap',
                wrapType => getHandleWrapType($handle),
                handle => $handle
            };
            
        } elsif ($util->isBuffer($stdio) || $util->isString($stdio)) {
            if (!$sync) {
                $cleanup->();
                die('Asynchronous forks do not support Buffer input: ' .
                    $util->inspect($stdio));
            }
        } else {
            $cleanup->();
            die('Incorrect value for stdio stream: ' .
                $util->inspect($stdio));
        }
        
        return $acc;
        
    }, []);
    
    return {stdio => $stdio, ipc => $ipc, ipcFd => $ipcFd};
}

sub _forkChild {
    my $fd = shift;
    #set process.send()
    my $p = createPipe(1);
    $p->open($fd);
    $p->unref();
    setupChannel(process, $p);
    my $refs = 0;
    process->on('newListener', sub {
        my ($this, $name) = @_;
        if ($name ne 'message' && $name ne 'disconnect') { return };
        if (++$refs == 1) { $p->ref() };
    });
    
    process->on('removeListener', sub {
        my ($this, $name) = @_;
        if ($name ne 'message' && $name ne 'disconnect') { return };
        if (--$refs == 0) { $p->unref() };
    });
}

sub _fork {
    my $modulePath = $_[0];
    #Get options and args arguments.
    my ($options, $args, $execArgv);
    if (CORE::ref $_[1] eq 'ARRAY') {
      $args = $_[1];
      $options = $util->_extend({}, $_[2]);
    } else {
        $args = [];
        $options = $util->_extend({}, $_[1]);
    }
    
    #Prepare arguments for fork:
    $execArgv = $options->{execArgv} || process->{execArgv};
    $args = $util->concat($execArgv, [$modulePath], $args);

    #Leave stdin open for the IPC channel. stdout and stderr should be the
    #same as the parent's if silent isn't set.
    $options->{stdio} = $options->{silent} ? ['pipe', 'pipe', 'pipe', 'ipc'] :
        [0, 1, 2, 'ipc'];

    $options->{execPath} = $options->{execPath} || process->execPath;
    return _spawn($options->{execPath}, $args, $options);
}

sub _spawn {
    my $opts = normalizeSpawnArguments(@_);
    my $file = $opts->{file};
    my $args = $opts->{args};
    my $options = $opts->{options};
    my $envPairs = $opts->{envPairs};
    my $child = __PACKAGE__->new();
    $child->spawn({
        file => $file,
        args => $args,
        cwd => $options ? $options->{cwd} : undef,
        windowsVerbatimArguments => !!($options && $options->{windowsVerbatimArguments}),
        detached => !!($options && $options->{detached}),
        envPairs => $envPairs,
        stdio => $options ? $options->{stdio} : undef,
        uid => $options ? $options->{uid} : undef,
        gid => $options ? $options->{gid} : undef
    });
    return $child;
}

sub normalizeSpawnArguments {
    #file, args, options
    my ($args, $options);
    my $file = $_[0];
    if (CORE::ref $_[1] eq 'ARRAY') {
        $args =  [ @{$_[1]} [ 0 .. (scalar @{$_[1]}) - 1 ] ];
        $options = $_[2];
    } else {
        $args = [];
        $options = $_[1];
    }

    if (!$options) {
        $options = {};
    }
    
    my $env = ($options ? $options->{env} : undef) || process->{env};
    _convertCustomFds($options);
    return {
        file => $file,
        args => $args,
        options => $options,
        envPairs => $env
    };
}

sub _convertCustomFds {
    my $options = shift;
    my $new = [];
    if ($options && $options->{customFds} && !$options->{stdio}) {
        my $fds = $options->{customFds};
        foreach my $fd (@{$fds}){
            my $val = $fd == -1 ? 'pipe' : $fd;
            push @{$new}, $val;
        }
        $options->{stdio} = $new;
    }
}

sub getSocketList {
    my ($type, $slave, $key) = @_;
    my $sockets = $slave->{_channel}->{sockets}->{$type};
    my $socketList = $sockets->{$key};
    if (!$socketList) {
        my $Construct = $type eq 'send' ? 'SocketListSend' : 'SocketListReceive';
        $socketList = $sockets->{key} = $Construct->new($slave, $key);
    }
    return $socketList;
}

my $handleConversion = {
    'net.Native' => {
        simultaneousAccepts => 1,
        send => sub {
            my ($this, $message, $handle) = @_;
            return $handle;
        },
        
        got => sub {
            my ($this, $message, $handle, $emit) = @_;
            #print STDERR Dumper $handle;
            $emit->($handle);
        }
    },
    
    'net.Server' => {
        simultaneousAccepts => 1,
        send => sub {
            my ($this, $message, $server) = @_;
            return $server->{_handle};
        },
        got => sub {
            my ($this, $message, $handle, $emit) = @_;
            my $server = Rum::Net::Server->new();
            $server->listen($handle, sub {
                $emit->($server);
            });
        }
    },
    
    'net.Socket' => {
        send => sub {
            my ($this, $message, $socket) = @_;
            if (!$socket->{_handle}){
                return;
            }
            
            #if the socket was created by net.Server
            if ($socket->{server}) {
                #the slave should keep track of the socket
                $message->{key} = $socket->{server}->{_connectionKey};
                my $firstTime = !$this->{_channel}->{sockets}->{send}->{$message->{key}};
                my $socketList = getSocketList('send', $this, $message->{key});
                #the server should no longer expose a .connection property
                #and when asked to close it should query the socket status from
                #the slaves
                if ($firstTime) { $socket->{server}->_setupSlave($socketList) }
                #Act like socket is detached
                $socket->{server}->{_connections}--;
            }
            
            #remove handle from socket object, it will be closed when the socket
            #will be sent
            my $handle = $socket->{_handle};
            $handle->{onread} = sub {};
            $socket->{_handle} = undef;
            
            return $handle;
        },
        
        postSend => sub {
            my ($this, $handle) = @_;
            #Close the Socket handle after sending it
            if ($handle) {
                $handle->close();
            }
        },
        
        got => sub  {
            my ($this, $message, $handle, $emit) = @_;
            my $socket = Rum::Net::Socket->new({handle => $handle});
            $socket->{readable} = $socket->{writable} = 1;
            #if the socket was created by net.Server we will track the socket
            if ($message->{key}) {
                #add socket to connections list
                my $socketList = getSocketList('got', $this, $message->{key});
                $socketList->add({
                    socket => $socket
                });
            }
            $emit->($socket);
        }
    }
};

my $INTERNAL_PREFIX = 'NODE_';
sub handleMessage {
    my ($target, $message, $handle) = @_;
    my $eventName = 'message';
    if ($message &&
        CORE::ref $message &&
        $util->isString($message->{cmd}) &&
        length $message->{cmd} > length $INTERNAL_PREFIX &&
        $INTERNAL_PREFIX eq substr $message->{cmd}, 0, length $INTERNAL_PREFIX ) {
        $eventName = 'internalMessage';
    }
    $target->emit($eventName, $message, $handle);
}

sub setupChannel {
    my ($target, $channel) = @_;
    
    $target->{_channel} = $channel;
    $target->{_handleQueue} = undef;
    
    my $decoder = Rum::StringDecoder->new('utf8');
    my $jsonBuffer = '';
    my @buffer;
    
    $channel->{buffering} = 0;
    
    $channel->{onread} = sub {
        my ($this, $nread, $pool, $recvHandle) = @_;
        #TODO Check that nread > 0.
        return if $nread == 0;
        if ($pool) {
            $jsonBuffer .= $decoder->write($pool->{base});
            my $i = index($jsonBuffer, "\n");
            while ( $i > 0 ) {
                my $hash = substr($jsonBuffer, 0, $i+1, '');
                my $message = eval "$hash";
                if (CORE::ref $message eq 'HASH' && $message->{cmd}
                                        && $message->{cmd} eq 'NODE_HANDLE'){
                    handleMessage($target, $message, $recvHandle);
                } else {
                    handleMessage($target, $message, undef);
                }
                
                $i = index($jsonBuffer, "\n");
            }
            $this->{buffering} = length $jsonBuffer != 0;
        } else {
            $this->{buffering} = 0;
            $target->disconnect();
            $channel->{onread} = sub{};
            $channel->close();
            maybeClose($target);
        }
    };
    
    #object where socket lists will live
    $channel->{sockets} = { got => {}, send => {} };
    
    #handlers will go through this
    $target->on('internalMessage', sub {
        my ($this, $message, $handle) = @_;
        #Once acknowledged - continue sending handles.
        if ($message->{cmd} eq 'NODE_HANDLE_ACK') {
            assert($util->isArray($target->{_handleQueue}));
            my $queue = $target->{_handleQueue};
            $target->{_handleQueue} = undef;
            
            foreach my $args (@{$queue}){
                $target->_send($args->{message}, $args->{handle}, 0);
            }
            
            #Process a pending disconnect (if any).
            if (!$target->{connected} && $target->{_channel} && !$target->{_handleQueue}){
                $target->_disconnect();
            }
            
            return;
        }
        
        if ($message->{cmd} ne 'NODE_HANDLE') { return };

        #Acknowledge handle receival. Don't emit error events (for example if
        #the other side has disconnected) because this call to send() is not
        #initiated by the user and it shouldn't be fatal to be unable to ACK
        #a message.
        $target->_send({ cmd => 'NODE_HANDLE_ACK' }, 0, 1);
        my $obj = $handleConversion->{$message->{type}};
        # Convert handle object
        $obj->{got}->($this, $message, $handle, sub {
            my $handle = shift;
            handleMessage($target, $message->{msg}, $handle);
        });
    });
    
    $target->{send} = sub {
        my ($this, $message, $handle) = @_;
        if (!$this->{connected}) {
            $this->emit('error', Rum::Error->new('channel closed'));
        } else {
            $this->_send($message, $handle, 0);
        }
    };
    
    $target->{_send} = sub {
        my ($this, $message, $handle, $swallowErrors) = @_;
        assert($this->{connected} || $this->{_channel});
        
        if ($util->isUndefined($message)) {
            Rum::Error->new('message cannot be undefined')->throw();
        }
        #package messages with a handle object
        if ($handle) {
            #this message will be handled by an internalMessage event handler
            $message = {
                cmd => 'NODE_HANDLE',
                type => undef,
                msg => $message
            };
            
            if (CORE::ref $handle eq 'Rum::Net::Socket') {
                $message->{type} = 'net.Socket';
            } elsif (CORE::ref $handle eq 'Rum::Net::Server') {
                $message->{type} = 'net.Server';
            } elsif (CORE::ref $handle eq 'Rum::Wrap::TCP' ||
                        CORE::ref $handle eq 'Rum::Wrap::Pipe' ) {
                $message->{type} = 'net.Native';
            } elsif (CORE::ref $handle eq 'dgram.Socket') {
                $message->{type} = 'dgram.Socket';
            } elsif (CORE::ref $handle eq 'Rum::Wrap::UDP') {
                $message->{type} = 'dgram.Native';
            } else {
                Rum::Error->new("This handle type can't be sent")->throw();
            }
            
            # Queue-up message and handle if we haven't received ACK yet.
            if ($this->{_handleQueue}) {
                push @{$this->{_handleQueue}}, { message => $message->{msg}, handle => $handle };
                return;
            }
            
            my $obj = $handleConversion->{$message->{type}};
            ## convert TCP object to native handle object
            $handle = $obj->{send}->($target, $message, $handle, $swallowErrors);
            ## If handle was sent twice, or it is impossible to get native handle
            ## out of it - just send a text without the handle.
            if (!$handle){
                $message = $message->{msg};
            }
            
        } elsif ($this->{_handleQueue} &&
               !(CORE::ref $message && $message->{cmd} eq 'NODE_HANDLE_ACK')) {
            #Queue request anyway to avoid out-of-order messages.
            push @{$this->{_handleQueue}}, {message => $message, handle => undef };
            return;
        }
        
        my $req = {oncomplete => sub{}};
        
        my $string;
        {
            local $Data::Dumper::Terse = 1;
            local $Data::Dumper::Indent = 0;
            $string = Dumper($message) . "\n";
        }
        
        my $err = $channel->writeUtf8String($req, $string, $handle);
        if ($err) {
            if (!$swallowErrors){
                $this->emit('error', errnoException($err, 'write'));
            }
        } elsif ($handle && !$this->{_handleQueue}) {
            $this->{_handleQueue} = [];
        }
        
        #FIXME
        #if ($obj && $obj->{postSend}) {
        #    $req->{oncomplete} = $obj->{postSend}->bind(undef, $handle);
        #}
        
        #If the master is > 2 read() calls behind, please stop sending.
        return $channel->{writeQueueSize} < (65536 * 2);
    };
    
    ## connected will be set to false immediately when a disconnect() is
    ## requested, even though the channel might still be alive internally to
    ## process queued messages. The three states are distinguished as follows:
    ## - disconnect() never requested: _channel is not null and connected
    ## is true
    ## - disconnect() requested, messages in the queue: _channel is not null
    ## and connected is false
    ## - disconnect() requested, channel actually disconnected: _channel is
    ## null and connected is false
    
    $target->{connected} = 1;
    $target->{disconnect} = sub {
        my $this = shift;
        if (!$this->{connected}) {
            $this->emit('error', Rum::Error->new('IPC channel is already disconnected'));
            return;
        }
        
        #Do not allow any new messages to be written.
        $this->{connected} = 0;
        
        # If there are no queued messages, disconnect immediately. Otherwise,
        # postpone the disconnect so that it happens internally after the
        # queue is flushed.
        if (!$this->{_handleQueue}) {
            $this->_disconnect();
        }
    };
    
    $target->{_disconnect} = sub {
        my $this = shift;
        assert($this->{_channel});
        # This marks the fact that the channel is actually disconnected.
        $this->{_channel} = undef;
        my $fired = 0;
        my $finish = sub {
            if ($fired) { return };
            $fired = 1;
            $channel->close();
            $target->emit('disconnect');
        };
        
        # If a message is being read, then wait for it to complete.
        if ($channel->{buffering}) {
            $this->once('message', $finish);
            $this->once('internalMessage', $finish);
            return;
        }
        
        process->nextTick($finish);
    };
    $channel->readStart();
}

sub disconnect {
    my $this = shift;
    $this->{disconnect}->($this);
}

sub _disconnect {
    my $this = shift;
    $this->{_disconnect}->($this);
}

sub send {
    my $this = shift;
    $this->{send}->($this, @_);
}

sub _send {
    my $this = shift;
    $this->{_send}->($this, @_);
}

sub _exec {
    #my $this = shift;
    my $opts = _normalizeExecArgs(@_);
    return _execFile($opts->{file},
                        $opts->{args},
                        $opts->{options},
                        $opts->{callback});
}

sub _execFile {
    #function(file /* args, options, callback */)
    my $file = $_[0];
    my ($args, $callback);
    my $options = {
        encoding => 'utf8',
        timeout => 0,
        maxBuffer => 200 * 1024,
        killSignal => 'SIGTERM',
        cwd => undef,
        env => undef
    };
    
    #Parse the parameters.
    if (CORE::ref $_[-1] eq 'CODE') {
        $callback = pop @_;
    }
    
    if ($util->isArray($_[1])) {
        $args = $_[1];
        $options = $util->_extend($options, $_[2]);
    } else {
        $args = [];
        $options = $util->_extend($options, $_[1]);
    }
    
    my $child = _spawn($file, $args, {
        cwd => $options->{cwd},
        env => $options->{env},
        windowsVerbatimArguments => !!$options->{windowsVerbatimArguments}
    });
    
    my $encoding;
    my $_stdout;
    my $_stderr;
    if ($options->{encoding} && $options->{encoding} ne 'buffer' &&
         Rum::Buffer::isEncoding($options->{encoding})) {
        $encoding = $options->{encoding};
        $_stdout = '';
        $_stderr = '';
    } else {
        $_stdout = [];
        $_stderr = [];
        $encoding = undef;
    }
    
    my $stdoutLen = 0;
    my $stderrLen = 0;
    my $killed = 0;
    my $exited = 0;
    my $timeoutId;
    my $ex = 0;
    my $exithandler = sub {
        my ($this, $code, $signal) = @_;
        if ($exited) { return }
        $exited = 1;
        if ($timeoutId) {
            clearTimeout($timeoutId);
            $timeoutId = undef;
        }
        
        if (!$callback) { return }
        #merge chunks
        my $stdout;
        my $stderr;
        if (!$encoding) {
            $stdout = Rum::Buffer->concat($_stdout);
            $stderr = Rum::Buffer->concat($_stderr);
        } else {
            $stdout = $_stdout;
            $stderr = $_stderr;
        }
        
        if ($ex) {
            #Will be handled later
        } elsif ($code == 0 && !$signal) {
            $callback->(undef, $stdout, $stderr);
            return;
        }
        
        my $cmd = $file;
        if (@{$args}){
            $cmd .= ' ' . join ' ', @{$args};
        }
        
        if (!$ex) {
            $ex = Rum::Error->new('Command failed: ' . $cmd . "\n" . $stderr);
            $ex->{killed} = $child->{killed} || $killed;
            #$ex->{code} = $code < 0 ? uv.errname(code) : $code;
            $ex->{signal} = $signal;
        }
        
        $ex->{cmd} = $cmd;
        $callback->($ex, $stdout, $stderr);
    };
    
    my $errorhandler = sub {
        my $this = shift;
        my $e = shift;
        $ex = $e;
        $child->stdout->destroy();
        $child->stderr->destroy();
        $exithandler->();
    };
    
    my $kill = sub {
        $child->stdout->destroy();
        $child->stderr->destroy();
        $killed = 1;
        try {
            $child->kill($options->{killSignal});
        } catch {
            $ex = $_;
            $exithandler->();
        };
    };
    
    if ($options->{timeout} > 0) {
        $timeoutId = setTimeout( sub {
            $kill->();
            $timeoutId = undef;
        }, $options->{timeout});
    }
    
    $child->stdout->addListener('data', sub {
        my ($this,$chunk) = @_;
        $stdoutLen += $util->BufferOrStringLength($chunk);
        if ($stdoutLen > $options->{maxBuffer}) {
            $ex = Rum::Error->new('stdout maxBuffer exceeded.');
            $kill->();
        } else {
            if (!$encoding) {
                push @{$_stdout}, $chunk;
            } else {
                $_stdout .= $chunk;
            }
        }
    });
    
    $child->stderr->addListener('data', sub {
        my ($this,$chunk) = @_;
        $stderrLen += $util->BufferOrStringLength($chunk);
        if ($stderrLen > $options->{maxBuffer}) {
            $ex = Rum::Error->new('stderr maxBuffer exceeded.');
            $kill->();
        } else {
            if (!$encoding){
                push @{$_stderr}, $chunk;
            } else {
                $_stderr .= $chunk;
            }
        }
    });
    
    if ($encoding) {
        $child->stderr->setEncoding($encoding);
        $child->stdout->setEncoding($encoding);
    }
    
    $child->addListener('close', $exithandler);
    $child->addListener('error', $errorhandler);
    return $child;
}

sub _normalizeExecArgs {
    my $command = $_[0];
    my ($file, $args, $options, $callback);
    if (CORE::ref $_[1] eq 'CODE') {
        $options = undef;
        $callback = $_[1];
    } else {
        $options = $_[1];
        $callback = $_[2];
    }
    
    if (Rum::process()->platform eq 'win32') {
        $file = 'cmd.exe';
        $args = ['/s', '/c', '"' . $command . '"'];
        #Make a shallow copy before patching so we don't clobber the user's
        #options object.
        $options = $util->_extend({}, $options);
        $options->{windowsVerbatimArguments} = 1;
    } else {
        $file = '/bin/sh';
        $args = ['-c', $command];
    }
    
    if ($options && $options->{shell}) {
        $file = $options->{shell};
    }

    return {
        cmd => $command,
        file => $file,
        args => $args,
        options => $options,
        callback => $callback
    };
}

my $sig_constant = \%Rum::Loop::Signal::signo;
sub kill {
    my $this = shift;
    my $sig = shift;
    my $signal;
    
    if ($util->isNumber($sig) && $sig == 0) {
        $signal = 0;
    } elsif (!defined $sig) {
        $signal = $sig_constant->{'TERM'};
    } else {
        $signal = $sig_constant->{$sig};
    }
    
    if (!defined $signal) {
        Rum::Error->new('Unknown signal: ' . $sig)->throw();
    }
    
    if ($this->{_handle}) {
        my $err = $this->{_handle}->kill($signal);
        if (!$err) {
            #success
            $this->{killed} = 1;
            return 1;
        }
        
        if ($err == ESRCH){
            #already died
        } elsif ($err == EINVAL || $err == ENOSYS){
            #The underlying platform doesn't support this signal.
            errnoException($err, 'kill')->throw();
        } else {
            #Other error, almost certainly EPERM.
            $this->emit('error', errnoException($err, 'kill'));
        }
    }
    
    # Kill didn't succeed.
    return 0;
}

#This object keep track of the socket there are sended
package SocketListSend; {
    use strict;
    use warnings;
    use base 'Rum::Events';
    use Rum::Error;
    
    sub new {
        my ($class, $slave, $key) = @_;
        return bless {
            key => $key,
            slave => $slave
        }, $class;
    }
    
    sub _request {
        my ($this, $msg, $cmd, $callback) = @_;
        my $self = $this;
        my ($onclose,$onreply);
        $onreply = sub {
            my $msg = shift;
            if ($msg->{cmd} && !($msg->{cmd} eq $cmd && $msg->{key} eq $self->{key})) { return };
            $self->{slave}->removeListener('disconnect', $onclose);
            $self->{slave}->removeListener('internalMessage', $onreply);
            $callback->(undef, $msg);
        };
        
        $onclose = sub {
            $self->{slave}->removeListener('internalMessage', $onreply);
            $callback->(Rum::Error->new('Slave closed before reply'));
        };
        
        if (!$this->{slave}->{connected}) { return $onclose };
        $this->{slave}->send($msg);
        $this->{slave}->once('disconnect', $onclose);
        $this->{slave}->on('internalMessage', $onreply);
    }
    
    sub close {
        my ($this,$callback) = @_;
        $this->_request({
            cmd => 'NODE_SOCKET_NOTIFY_CLOSE',
            key => $this->{key}
        }, 'NODE_SOCKET_ALL_CLOSED', $callback);
    }
    
    sub getConnections {
        my ($this, $callback) = @_;
        $this->_request({
            cmd => 'NODE_SOCKET_GET_COUNT',
            key => $this->{key}
        }, 'NODE_SOCKET_COUNT', sub {
            my ($err, $msg) = @_;
            if ($err) { return $callback->($err) }
            $callback->(undef, $msg->{count});
        });
    }
};

#This object keep track of the socket there are received
package SocketListReceive; {
    use strict;
    use base 'Rum::Events';
    sub new {
        my ($class, $slave, $key) = @_;
        my $this;
        my $self = $this = bless {}, $class;
        $this->{connections} = 0;
        $this->{key} = $key;
        $this->{slave} = $slave;

        my $onempty = sub {
            if (!$self->{slave}->{connected}) { return }
            $self->{slave}->send({
                cmd => 'NODE_SOCKET_ALL_CLOSED',
                key => $self->{key}
            });
        };
        
        $this->{slave}->on('internalMessage', sub {
            my ($this, $msg) = @_;
            if ($msg->{key} ne $self->{key}){ return }
            if ($msg->{cmd} eq 'NODE_SOCKET_NOTIFY_CLOSE') {
                # Already empty
                if ($self->{connections} == 0) { return $onempty->() }
                # Wait for sockets to get closed
                $self->once('empty', $onempty);
            } elsif ($msg->{cmd} eq 'NODE_SOCKET_GET_COUNT') {
                if (!$self->{slave}->{connected}) { return }
                $self->{slave}->send({
                    cmd => 'NODE_SOCKET_COUNT',
                    key => $self->{key},
                    count => $self->{connections}
                });
            }
        });
        return $this;
    }
    
    sub add {
        my ($this, $obj) = @_;
        my $self = $this;
        $this->{connections}++;
        #Notify previous owner of socket about its state change
        $obj->{socket}->once('close', sub {
            $self->{connections}--;
            if ($self->{connections} == 0) { $self->emit('empty') }
        });
    }
};

1;

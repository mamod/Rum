package Rum::Loop::Process::Win32;
use strict;
use warnings;


package
        Rum::Loop::Process;
use Rum::Loop::Flags qw/:Process :IO :Platform :Stdio :Stream/;
use Rum::Loop::Utils 'assert';
use Rum::Loop::Queue;
use POSIX  qw[:errno_h :fcntl_h setsid :sys_wait_h];
use Socket;
use Rum::Loop::Core ();
use Data::Dumper;
use Win32::Process;
use Win32;
use Cwd;

#process constants
my $NULL = Rum::Loop::Core::NULL();
my $DETACHED_PROCESS = 0x00000008;
my $CREATE_NEW_PROCESS_GROUP = 0x00000200;
my $CREATE_UNICODE_ENVIRONMENT = 0x00000400;

#store current workin path
my $DIR = getcwd();

sub ErrorReport{
    print Win32::FormatMessage( Win32::GetLastError() );
}

sub _getFD {
    return defined(fileno $_[0]) ?
        fileno $_[0] : $_[0];
}

sub process_child_init {
    my $options = shift;
    my $stdio_count = shift;
    my $pipes = shift;
    my $error_fd = shift;
    my $close_fd = 0;
    my $use_fd = 0;
    my $use_handle = -1;
    my $fd = 0;
    
    my $handles = {};
    my @shared_handles;
    my $o_count = $stdio_count;
    
    my $process_flags = $CREATE_UNICODE_ENVIRONMENT;
    
    if ($options->{flags} & $PROCESS_DETACHED) {
        $process_flags |= $DETACHED_PROCESS | $CREATE_NEW_PROCESS_GROUP;
    }
    
    my @studioHandles = (
        -1,
        -1,
        -1
    );
    
    my @closeHandles;
    for ($fd = 0; $fd < $stdio_count; $fd++) {
        $use_handle   = $pipes->[$fd]->[2];
        $close_fd = _getFD($pipes->[$fd]->[0]);
        $use_fd   = _getFD($pipes->[$fd]->[1]);
        
        if ($use_handle > 0) {
            if ($fd <= 2) {
                $studioHandles[$fd] = $use_handle;
            } else {
                push @shared_handles, "$fd,$use_handle";
            }
        }
    }
    
    if ($options->{cwd} && !POSIX::chdir($options->{cwd})) {
        return;
    }
    
    if ($options->{env}) {
        %ENV = %{ $options->{env} };
    }
    
    $! = 0;
    $ENV{NODE_WIN_HANDLES} = join "#", @shared_handles;
    
    #$studioHandles[2] = Rum::Loop::Core::GetStdHandle(-12); #debug
    
    my $PACK = "L!17";
    my $PACK_SIZE = length pack($PACK);
    my $startUpinfo = pack ($PACK,
                      ($PACK_SIZE,0,0,0,0,0,0,0,0,0,0,0x00000100,0,0,
                       $studioHandles[0],$studioHandles[1],$studioHandles[2]));
    
    my $processInfo = pack "I4", (0,0,0,0);
    my $args = join " ", @{$options->{args}};
    
    $options->{file} = "perl runner.pl" if $options->{file} =~ /Rum\.bat/i;
    #FIXME: escape args!
    if (!Rum::Loop::Core::CreateProcess($NULL,
              $options->{file} . " " . $args,
              $NULL,
              $NULL,
              #do not inherit when detaching a process
              ($options->{flags} & $PROCESS_DETACHED) ? 0 : 1,
              $process_flags,
              $NULL,
              $NULL,
              $startUpinfo,
              $processInfo)) {
        
        $! = $^E+0;
        return;
    }
    
    my @processInfo = unpack "I4", $processInfo;
    select undef,undef,undef,.05;
    
    #restore working path
    if ($options->{cwd}) {
        POSIX::chdir($DIR) or return;
    }
    
    if ($! > 0) {
        return;
    }
    
    return \@processInfo;
}

sub rm_process_init_stdio {
    my ($container, $fds, $i) = @_;
    my $mask = $IGNORE | $CREATE_PIPE | $INHERIT_FD | $INHERIT_STREAM;
    
    if ($i <= 2) {
        my $null = POSIX::open("NUL", $i == 0 ? O_RDONLY : O_RDWR);
        my $null_handle = Rum::Loop::Core::FdGetOsFHandle( $null ) or return;
        $fds->[2] = $null_handle;
    }
    
    return 1 if !$container;
    
    my $switch = $container->{flags} & $mask;
    my $fd;
    if ($switch == $IGNORE) {
        return 1;
    } elsif ($switch == $CREATE_PIPE){
        assert($container->{data}->{stream});
        if ($container->{data}->{stream}->{type} ne 'NAMED_PIPE') {
            $! = EINVAL;
            return;
        } else {
            _make_socketpair($fds, 0) or return;
            my $fh = $fds->[1];
            my $inherit_handle = -1;
            if ($i > 2) {
                $inherit_handle = Rum::Loop::Core::make_inheritable($fh);
            } else {
                $inherit_handle = Rum::Loop::Core::duplicate_file($fh);
            }
            $fds->[2] = $inherit_handle;
            return 1;
        }
    } elsif ($switch == $INHERIT_FD || $switch == $INHERIT_STREAM) {
        if ($container->{flags} & $INHERIT_FD) {
            $fd = $container->{data}->{fd};
        } else {
            $fd = Rum::Loop::stream_fd($container->{data}->{stream});
        }
        
        if ($fd == -1){
            $! = EINVAL;
            return;
        }
        
        ##duplicate fd
        my $dupHandle = Rum::Loop::Core::duplicate_file($fd) or die $^E;
        $fds->[2] = $dupHandle;
        return 1;
        
    } else {
        die EINVAL;
    }
}

sub spawn {
    my $loop = shift;
    my $process = shift;
    my $options = shift;
    
    my $signal_pipe = [ -1, -1 ];
    
    my $stdio_count = 0;
    my $q = {};
    my $r = 0;
    my $pid = 0;
    my $err = 0;
    my $exec_errorno = 0;
    my $i = 0;
    
    assert($options->{file}, "options file required");
    assert(!($options->{flags} & ~($PROCESS_DETACHED |
                              $PROCESS_SETGID |
                              $PROCESS_SETUID |
                              $PROCESS_WINDOWS_HIDE |
                              $PROCESS_WINDOWS_VERBATIM_ARGUMENTS)));
    
    $loop->handle_init($process, 'PROCESS');
    $process->{queue} = QUEUE_INIT($process);
    
    $options->{stdio_count} ||= 0;
    $stdio_count = $options->{stdio_count};
    if ($stdio_count < 3) {
        $stdio_count = 3;
    }
    
    $! = ENOMEM;
    
    my $pipes = [];
    
    for ($i = 0; $i < $stdio_count; $i++) {
        $pipes->[$i]->[0] = -1;
        $pipes->[$i]->[1] = -1;
        $pipes->[$i]->[2] = -1;
    }
   
    for ($i = 0; $i < $stdio_count; $i++) {
        if (!rm_process_init_stdio($options->{stdio}->[$i], $pipes->[$i], $i)){
            goto error;
        }
    }
    
    $! = 0;
    my $ret_val = process_child_init($options, $stdio_count, $pipes);
    
    $process->{exit_cb} = $options->{exit_cb};
    $process->{shared_handles} = $ENV{NODE_WIN_HANDLES};
    $process->{pid} = 0;
    if (!$ret_val) {
        #error
    } else {
        $process->{process_handle} = $ret_val->[0] || -1;
        $process->{pid} = $ret_val->[2] || 0;
        
        #close thread handle
        Rum::Loop::Core::CloseHandle($ret_val->[1]);
    }
    
    $process->{status} = 0;
    
    #Set IPC pid to all IPC pipes.
    for ($i = 0; $i < $options->{stdio_count}; $i++) {
        my $fdopt = $options->{stdio}->[$i];
        if ($fdopt->{flags} & $CREATE_PIPE &&
            $fdopt->{data}->{stream}->{type} eq 'NAMED_PIPE' &&
            $fdopt->{data}->{stream}->{ipc}) {
            $fdopt->{data}->{stream}->{ipc_pid} = $process->{pid};
        }
    }
    
    for ($i = 0; $i < $options->{stdio_count}; $i++) {
        my $ret = _process_open_stream($options->{stdio}->[$i], $pipes->[$i], $i == 0);
        if ($ret){
            next;
        }
        
        while ($i--) {
            _process_close_stream($options->{stdio}->[$i]);
        }
        goto error;
    }
    
    #Only activate this handle if exec() happened successfully
    if ( $process->{pid} ) {
        $process->{pipes} = $pipes;
        $q = process_queue($loop, $process->{pid}, $process);
        QUEUE_INSERT_TAIL($q, $process->{queue});
        $loop->handle_start($process);
        
        #OPTIMIZATION : currently we make a timer loop to check for each
        #process exit code - possible optimization using winapi
        #WaitForMultipleObjects or WaitForSingleObject
        if (!Rum::Loop::is_active($loop->{children_watcher})) {
            $loop->unref($loop->{children_watcher});
            $loop->timer_start($loop->{children_watcher},sub{
                _chld($loop->{child_watcher}, 20);
            },100,100);
        }
    }
    
    undef $pipes;
    return $! ? 0 : 1;
    
    error: {
        if ($pipes) {
            for ($i = 0; $i < $stdio_count; $i++) {
                if ( $i < $options->{stdio_count}){
                    if ($options->{stdio}->[$i]->{flags} &
                         ($INHERIT_FD | $INHERIT_STREAM)){
                        next;
                    }
                }
                
                if ($pipes->[$i]->[0] != -1){
                    POSIX::close($pipes->[$i]->[0]) or die $!;
                }
                
                if ($pipes->[$i]->[1] != -1){
                    POSIX::close($pipes->[$i]->[1]) or die $!;
                }
            }
            undef $pipes;
        }
    };
    
    return $! ? 0 : 1;
}


sub _chld2 {
    my $handle = shift;
    my $signum = shift;
    
    my $process;
    my $loop;
    my $exit_status = 0;
    my $term_signal = 0;
    my $i;
    my $status = 0;
    my $pid;
    my $pending = {};
    
    my ($h,$q);
    
    #assert($signum == 2); 
    $pending = QUEUE_INIT($handle);
    $loop = $handle->{loop};
    
    foreach my $pid (keys %{ $loop->{process_handles} }){
        $h = $loop->{process_handles}->{$pid};
        $q = QUEUE_HEAD($h);
        
        while ($q != $h) {
            $process = $q->{data};
            
            $q = $q->{next};
            do {
                $pid = waitpid($process->{pid}, WNOHANG);
            } while ($pid == -1 && $! == EINTR);
            
            if ($pid == 0) {
                next;
            }
            
            if ($pid == -1) {
                if ($! != ECHILD){
                    exit();
                }
                next;
            }
            
            $process->{status} = $?;
            my $data = $process->{queue}->{data};
            QUEUE_REMOVE($process->{queue});
            $process->{queue}->{data} = $data;
            QUEUE_INSERT_TAIL($pending, $process->{queue});
        }
        
        while (!QUEUE_EMPTY($pending)) {
            
            $q = QUEUE_HEAD($pending);
            $process = $q->{data};
            
            QUEUE_REMOVE($q);
            QUEUE_INIT2($q,$process);
            
            $loop->handle_stop($process);
            
            if (!$process->{exit_cb}) {
                next
            }
            
            $exit_status = $process->{status}  >> 8;
            
            
            
            $term_signal = 0;
            
            $process->{exit_cb}->($process, $exit_status, $term_signal);
        }
    }
}

sub _chld {
    my $handle = shift;
    my $signum = shift;
    
    my $process;
    my $loop;
    my $exit_status = 0;
    my $term_signal = 0;
    my $i;
    my $status = 0;
    my $pid;
    my $pending = {};
    my ($h,$q);
    
    $pending = QUEUE_INIT($handle);
    $loop = $handle->{loop};
    
    foreach my $pid (keys %{ $loop->{process_handles} }){
        
        $h = $loop->{process_handles}->{$pid};
        $q = QUEUE_HEAD($h);
        
        while ($q != $h) {
            $process = $q->{data};
            $q = $q->{next};
            
            my $status = "\0\0\0\0";
            Rum::Loop::Core::GetExitCodeProcess($process->{process_handle},$status)
                    or die $^E;
            $status = unpack "V", $status;
            
            if ($status == 259) { # 259 == STILL_ACTIVE
                next;
            }
            
            $process->{status} = $status;
            my $data = $process->{queue}->{data};
            QUEUE_REMOVE($process->{queue});
            $process->{queue}->{data} = $data;
            QUEUE_INSERT_TAIL($pending, $process->{queue});
        }
        
        while (!QUEUE_EMPTY($pending)) {
            $q = QUEUE_HEAD($pending);
            $process = $q->{data};
            
            QUEUE_REMOVE($q);
            QUEUE_INIT2($q,$process);
            $loop->handle_stop($process);
            
            foreach my $pipe (@{$process->{pipes}}) {
                Rum::Loop::Core::CloseHandle($pipe->[2]);
            }
            
            #close process handle
            Rum::Loop::Core::CloseHandle($process->{process_handle}) or die $^E;
            
            if (!$process->{exit_cb}) {
                next;
            }
            
            $exit_status = 0;
            $term_signal = 0;
            $exit_status = $process->{status};
            $process->{exit_cb}->($process, $exit_status, $term_signal);
        }
    }
}

sub process_queue {
    my $loop = shift;
    my $pid = shift;
    my $process = shift;
    $loop->{process_handles}->{$pid} = QUEUE_INIT($process);
    return $loop->{process_handles}->{$pid};
}

1;

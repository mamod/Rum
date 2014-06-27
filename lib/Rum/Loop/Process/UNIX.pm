package Rum::Loop::Process::UNIX;
use strict;
use warnings;


package
        Rum::Loop::Process;

use Rum::Loop::Flags qw/:Process :IO :Platform :Stdio :Stream/;
use Rum::Loop::Utils 'assert';
use Rum::Loop::Queue;
use POSIX  qw[:errno_h :fcntl_h setsid :sys_wait_h];
use Data::Dumper;


sub _getFD {
    return defined(fileno $_[0]) ?
        fileno $_[0] : $_[0];
}

sub __write_int {
    my $fh = shift;
    my $val = shift . '';
    my $n = 0;
    do {
        $n = syswrite($fh, $val, length $val);
    } while (!defined $n && $! == EINTR);

    if (!defined $n && $! == EPIPE) {
        return; # parent process has quit
    }
    
    assert($n == length $val);
}

sub process_child_init {
    
    my $options = shift;
    my $stdio_count = shift;
    my $pipes = shift;
    my $error_fd = shift;
    my $close_fd = 0;
    my $use_fd = 0;
    my $fd = 0;
    
    if ($options->{flags} & $PROCESS_DETACHED) {
        setsid();
    }
    
    my @studio = (
        *STDIN,
        *STDOUT,
        *STDERR
    );
    
    for ($fd = 0; $fd < $stdio_count; $fd++) {
        $close_fd = _getFD($pipes->[$fd]->[0]);
        $use_fd   = _getFD($pipes->[$fd]->[1]);
        
        if ($use_fd < 0) {
            if ($fd >= 3){
                next;
            } else {
                $use_fd = POSIX::open("/dev/null", $fd == 0 ? O_RDONLY : O_RDWR);
                $close_fd = $use_fd;
                if (!$use_fd) {
                    __write_int($error_fd, $!+0);
                    exit(127);
                }
            }
        }
        
        if ($fd == $use_fd) {
            Rum::Loop::Core::cloexec($studio[$use_fd], 0);
        }
        else {
            POSIX::dup2($use_fd, $fd) or die $!;
        }
        
        if ($fd <= 2) {
            Rum::Loop::Core::nonblock($studio[$fd], 0);
        }
        
        if ($close_fd >= $stdio_count){
            Rum::Loop::Core::__close($close_fd);
        }
    }
    
    for ($fd = 0; $fd < $stdio_count; $fd++) {
        $use_fd = _getFD($pipes->[$fd]->[1]);
        if ($use_fd >= 0 && $fd != $use_fd){
            POSIX::close($use_fd) or die $!;
        }
    }
    
    if ($options->{cwd} && !POSIX::chdir($options->{cwd})) {
        __write_int($error_fd, $!+0);
        exit(127);
    }
    
    if ($options->{flags} & ($PROCESS_SETUID | $PROCESS_SETGID)) {
        # When dropping privileges from root, the `setgroups` call will
        # remove any extraneous groups. If we don't call this, then
        # even though our uid has dropped, we may still have groups
        # that enable us to do super-user things. This will fail if we
        # aren't root, so don't bother checking the return value, this
        # is just done as an optimistic privilege dropping function.
        die;
        #SAVE_ERRNO(setgroups(0, NULL));
    }
    
    if (($options->{flags} & $PROCESS_SETGID) && !POSIX::setgid($options->{gid})) {
        __write_int($error_fd, $!+0);
        exit(127);
    }
    
    if (($options->{flags} & $PROCESS_SETUID) && !POSIX::setuid($options->{uid})) {
        __write_int($error_fd, $!+0);
        exit(127);
    }
    
    if ($options->{env}) {
        %ENV = %{ $options->{env} };
    }
    
    $! = 0;
    
    my $e = exec( $options->{file}, @{$options->{args}} );
    __write_int($error_fd, $!+0);
    exit(127);
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
    }
    
    for ($i = 0; $i < $options->{stdio_count}; $i++) {
        if ( !_process_init_stdio($options->{stdio}->[$i], $pipes->[$i]) ){
            goto error;
        }
    }
    
    # This pipe is used by the parent to wait until
    # the child has called `execve()`. We need this
    # to avoid the following race condition:
    
    # if ((pid = fork()) > 0) {
    # kill(pid, SIGTERM);
    # }
    # else if (pid == 0) {
    # execve("/bin/cat", argp, envp);
    # }
    
    # The parent sends a signal immediately after forking.
    # Since the child may not have called `execve()` yet,
    # there is no telling what process receives the signal,
    # our fork or /bin/cat.
    
    # To avoid ambiguity, we create a pipe with both ends
    # marked close-on-exec. Then, after the call to `fork()`,
    # the parent polls the read end until it EOFs or errors with EPIPE.
    
    Rum::Loop::Core::make_pipe($signal_pipe, 0) or goto error;
    
    $loop->signal_start($loop->{child_watcher}, \&_chld, 'CHLD');
    
    # Acquire write lock to prevent opening new fds in worker threads
    # uv_rwlock_wrlock(&loop->cloexec_lock);
    $pid = fork();
    
    if (!defined $pid) {
        $err = $!;
        #uv_rwlock_wrunlock(&loop->cloexec_lock);
        Rum::Loop::Core::__close($signal_pipe->[0]);
        Rum::Loop::Core::__close($signal_pipe->[1]);
        goto error;
    }
    
    if ($pid == 0) {
        process_child_init($options, $stdio_count, $pipes, $signal_pipe->[1]);
        #kill 'ABRT', $$;
        exit;
    } else {
        Rum::Loop::Core::__close($signal_pipe->[1]);
    }
    
    #Release lock in parent process
    #uv_rwlock_wrunlock(&loop->cloexec_lock);
    
    $process->{status} = 0;
    $exec_errorno = 0;
    $! = 0;
    do {
        $r = read($signal_pipe->[0], $exec_errorno, 24);
    } while (!defined $r && $! == EINTR);
    
    if ($r == 0){
        #okay, EOF
    } elsif ($r) {
        $! = $exec_errorno;
        #okay, read errorno
    } elsif (!defined $r && $! == EPIPE){
        #okay, got EPIPE
    } else {
        die;
    }
    
    Rum::Loop::Core::__close($signal_pipe->[0]);
    
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
    if (!$exec_errorno) {
        $q = process_queue($loop, $pid, $process);
        QUEUE_INSERT_TAIL($q, $process->{queue});
        $loop->handle_start($process);
    }
    
    $process->{pid} = $pid;
    $process->{exit_cb} = $options->{exit_cb};
    
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
            
            $exit_status = 0;
            
            if (WIFEXITED( $process->{status} )) {
                $exit_status = WEXITSTATUS( $process->{status} );
            }
            
            $term_signal = 0;
            if (WIFSIGNALED($process->{status})){
                $term_signal = WTERMSIG($process->{status});
            }
            
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

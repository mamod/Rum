package Rum::Loop::Process;
use strict;
use warnings;
use Rum::Loop::Queue;
use Rum::Loop::Flags qw(:IO :Stream :Stdio);
use POSIX  qw[:errno_h :fcntl_h setsid :sys_wait_h];
use Socket;
use Data::Dumper;

use base qw/Exporter/;
our @EXPORT = qw (
    spawn
    process_close
    stdio_container
);

if ($^O eq 'MSWin32') {
    require Rum::Loop::Process::Win32;
} else {
    require Rum::Loop::Process::UNIX;
}

sub stdio_container {
    my $len = shift;
    my $t = [];
    
    for (1 .. $len){
        push @{$t}, {
            flags => 0
        };
    }
    
    return $t;
}

sub _make_socketpair {
    my ($fds, $flags) = @_;
    
    socketpair(my $fd0, my $fd1, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
    ||  die "socketpair: $!";
    
    $fd0->autoflush(1);
    $fd1->autoflush(1);
    $fds->[0] = $fd0;
    $fds->[1] = $fd1;
    Rum::Loop::Core::cloexec($fds->[0], 1);
    Rum::Loop::Core::cloexec($fds->[1], 1);
    
    if ($flags & $NONBLOCK) {
        Rum::Loop::Core::nonblock($fds->[0], 1);
        Rum::Loop::Core::nonblock($fds->[1], 1);
    }
    
    return 1;
}

sub process_close {
    my $loop = shift;
    my $handle = shift;
    #TODO stop signal watcher when this is the last handle
    QUEUE_REMOVE($handle->{queue});
    $loop->handle_stop($handle);
}

sub _process_open_stream {
    my ($container, $pipefds, $writable) = @_;
    
    if (!($container->{flags} & $CREATE_PIPE) || $pipefds->[0] < 0) {
        return 1;
    }
   
    if (Rum::Loop::Core::__close($pipefds->[1])) {
        if ($! != EINTR && $! != EINPROGRESS) {
            die $!;
        }
    }
    
    $pipefds->[1] = -1;
    Rum::Loop::Core::nonblock($pipefds->[0], 1);
    my $flags = 0;
    if ($container->{data}->{stream}->{type} eq 'NAMED_PIPE' &&
        ($container->{data}->{stream}->{ipc}) ) {
        $flags = $STREAM_READABLE | $STREAM_WRITABLE;
    } elsif ($writable) {
        $flags = $STREAM_WRITABLE;
    } else {
        $flags = $STREAM_READABLE;
    }
    
    Rum::Loop::stream_open($container->{data}->{stream}, $pipefds->[0], $flags) or return;
    
    return 1;
}

sub _process_init_stdio {
    my ($container, $fds) = @_;
    my $mask = $IGNORE | $CREATE_PIPE | $INHERIT_FD | $INHERIT_STREAM;
    
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
            return 1;
        }
    } elsif ($switch == $INHERIT_FD || $switch == $INHERIT_STREAM){
        if ($container->{flags} & $INHERIT_FD) {
            $fd = $container->{data}->{fd};
        } else {
            $fd = Rum::Loop::stream_fd($container->{data}->{stream});
        }
        if ($fd == -1){
            $! = EINVAL;
            return;
        }
        $fds->[1] = $fd;
        return 1;
    } else {
        die EINVAL;
    }
}

1;

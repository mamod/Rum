package Rum::Loop::Core;
use strict;
use warnings;
use Data::Dumper;
use Socket;
use Rum::Loop::Flags qw[$NONBLOCK :Platform];
use Rum::Loop::Utils 'assert';
use POSIX ':errno_h';
use base qw/Exporter/;
our @EXPORT = qw (
    make_pipe
    cloexec
    nonblock
);

if ($^O =~ /mswin/i) {
    require Rum::Loop::Core::Win32;
} else {
    require Rum::Loop::Core::UNIX;
}

sub __close {
    my $fh = shift;
    my $rc;
    my $fd = ref $fh ? fileno $fh : $fh;
    
    #Catch uninitialized io_watcher.fd bugs.
    assert(defined $fd && $fd > -1, "uninitialized file handle"); 
    
    #Catch stdio close bugs.
    assert($fd != fileno *STDERR && $fd != fileno *STDIN
           && $fd != fileno *STDOUT, "can't close stdio files");
    
    my $saved_errno = $!;
    $rc = _doclose($fh);
    if (!$rc) {
        $rc = $!;
        if ($! == EINTR) {
            $rc = EINPROGRESS; # For platform/libc consistency.
        }
        $! = $saved_errno;
        return $rc;
    }
    
    $! = $saved_errno;
    return 0;
}

sub _doclose {
    my $h = shift;
    my $ret;
    if (ref $h) {
        $ret = CORE::close $h;
    } else {
        $ret = POSIX::close($h);
    }
    return $ret;
}

sub _accept {
    my $sockfh = shift;
    my $peerfd;
    my $ret;
    assert(fileno $sockfh >= 0);
    $! = 0;
    while (1) {
        if (0) {
            die;
            Linux::Socket::Accept4::accept4($peerfd, $sockfh,
                        Linux::Socket::Accept4::SOCK_NONBLOCK() |
                        Linux::Socket::Accept4::SOCK_CLOEXEC())
                        && return $peerfd;
            
            if ($! == EINTR) {
                next;
            }
            
            if ($! != ENOSYS) {
                return;
            }
        } else {
            if (!CORE::accept($peerfd,$sockfh)) {
                if ($! == EINTR) {
                    next;
                }
                return;
            }
            
            $ret = Rum::Loop::Core::cloexec($peerfd, 1);
            if ($ret) {
                $ret = Rum::Loop::Core::nonblock($peerfd, 1);
            }
            
            if (!$ret) {
                __close($peerfd);
                return;
            }
            return $peerfd;
        }
    }
}


sub make_pipe {
    my ($fds, $flags) = @_;
    my ($fd0, $fd1);
    
    if ($isWin) {
        socketpair($fd0, $fd1, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
            or return;
    } else {
        pipe($fd0, $fd1);
    }
    
    $fds->[0] = $fd0;
    $fds->[1] = $fd1;
    
    ##perl does not gurantee flushing
    $fd0->autoflush(1);
    $fd1->autoflush(1);
    
    ##this is perl default behaviour
    ##but we will try it anyway to make sure
    cloexec($fds->[0], 1);
    cloexec($fds->[1], 1);
    if ($flags) {
        nonblock($fds->[0], 1);
        nonblock($fds->[1], 1);
    }
    
    return 1;
}

1;

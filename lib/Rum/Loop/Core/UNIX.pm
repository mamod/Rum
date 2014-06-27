package Rum::Loop::Core::UNIX;


package
        Rum::Loop::Core;
use strict;
use warnings;
use Rum::Loop::Core;
use Rum::Loop::Flags qw($NONBLOCK :Platform);
use POSIX qw(EINTR);
use Fcntl;
use Data::Dumper;

sub cloexec {
    my ($fh, $set) = @_;
    my $flags;
    my $r;
    
    do {
        $r = fcntl($fh, F_GETFD,0);
    } while (!$r && $! == EINTR);
    
    if (!$r) {
        return;
    }
    
    #Bail out now if already set/clear.
    if (!!($r & FD_CLOEXEC) == !!$set) {
        return 1;
    }
    
    if ($set) {
        $flags = $r | FD_CLOEXEC;
    } else {
        $flags = $r & ~FD_CLOEXEC;
    }
    
    do {
        $r = fcntl($fh, F_SETFD, $flags);
    } while (!$r && $! == EINTR);
    
    if (!$r) {
        return;
    }
    
    return 1;
}

sub nonblock {
    my ($fh, $set) = @_;
    my $flags;
    my $r;
    
    do {
        $r = fcntl($fh, F_GETFL, 0);
    } while (!$r && $! == EINTR);
    
    if (!$r) {
        return;
    }
    
    #/* Bail out now if already set/clear. */
    if (!!($r & O_NONBLOCK) == !!$set) {
        return 1;
    }
    
    if ($set) {
        $flags = $r | O_NONBLOCK;
    } else {
        $flags = $r & ~O_NONBLOCK;
    }
    
    do {
        $r = fcntl($fh, F_SETFL, $flags);
    } while (!$r && $! == EINTR);
    
    if (!$r) {
        return;
    }
    
    return 1;
}

sub disable_stdio_inheritance {
    
}

1;

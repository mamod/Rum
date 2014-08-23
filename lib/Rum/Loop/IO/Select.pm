package Rum::Loop::IO::Select;
use strict;
use warnings;
use Data::Dumper;
use Rum::Loop::Queue;
use Rum::Loop::Utils 'assert';
use POSIX qw(:errno_h);
use Rum::Loop::Flags qw[:IO];

use base qw/Exporter/;
our @EXPORT = qw (
    EPOLLIN
    EPOLLOUT
    EPOLLRDHUP
    EPOLLPRI
    EPOLLERR
    EPOLLHUP
    EPOLLET
);

my $EPOLLIN  = 2;
my $EPOLLOUT = 4;
my $EPOLLERR = 8;
my $EPOLLHUP = 10;

sub EPOLLIN      { $EPOLLIN  }
sub EPOLLOUT     { $EPOLLOUT }
sub EPOLLPRI     { 0x0002 }
sub EPOLLERR     { $EPOLLERR }
sub EPOLLHUP     { 0x0010 }

sub Rum::Loop::IO::platform_invalidate_fd {
    my $loop = shift;
    my $fd = shift;
    my $ev = shift;
    
    #silent errors
    eval {
        vec($loop->{sEvents}->[0], $fd, 1) = 0;
        vec($loop->{sEvents}->[1], $fd, 1) = 0;
        vec($loop->{sEvents}->[2], $fd, 1) = 0;
    };
}

sub Rum::Loop::IO::io_poll {
    my ($loop, $timeout) = @_;
    my $pe;
    my $e;
    my $q;
    my $w;
    my $base;
    my $diff;
    my $nevents;
    my $count;
    my $nfds;
    my $fd;
    my $op;
    my $i;
    
    if ( $loop->{nfds} == 0 ) {
        assert( QUEUE_EMPTY($loop->{watcher_queue}) );
        #select(undef,undef,undef,.001);
        return;
    }
    
    $count = 50;
    while (!QUEUE_EMPTY($loop->{watcher_queue}) && $count-- ) {
        $q = QUEUE_HEAD($loop->{watcher_queue});
        $w = $q->{data};
        QUEUE_REMOVE($q);
        QUEUE_INIT2($q, $w);
        
        assert($w->{pevents} != 0);
        assert($w->{fd} >= 0);
        assert($w->{fd} < $loop->{nwatchers});
        
        my $ev = $w->{pevents};
        my $fd = $w->{fd};
        
        if ($w->{events} == 0){
            if ($ev & $EPOLLIN){
                vec($loop->{sEvents}->[0], $fd, 1) = 1;
            }
            
            if ($ev & $EPOLLOUT){
                vec($loop->{sEvents}->[1], $fd, 1) = 1;
            }
            
            if ($ev & $EPOLLERR){
                vec($loop->{sEvents}->[2], $fd, 1) = 1;
            }
            
        } else {
            die "shouldn't get here!!!";
        }
    }
    
    assert($timeout >= -1);
    $base = $loop->{time};
    
    $count = 48; # Benchmarks suggest this gives the best throughput.
    
    my $rout = '';
    my $wout = '';
    my $eout = '';
    my $wait;
    if (!QUEUE_EMPTY($loop->{watcher_queue})) {$timeout = 0}
    for (;;) {
        $wait = $timeout == -1 ? undef : $timeout/1000;
        
        $nfds = select($rout=$loop->{sEvents}->[0],
                    $wout=$loop->{sEvents}->[1],
                    $eout=$loop->{sEvents}->[2],$wait);
        
        #print Dumper $nfds;
        # Update loop->time unconditionally. It's tempting to skip the update when
        # timeout == 0 (i.e. non-blocking poll) but there is no guarantee that the
        # operating system didn't reschedule our process while in the syscall.
        
        $loop->update_time();
        
        if ($nfds == 0) {
            assert($timeout != -1);
            return;
        }
        
        if ($nfds == -1) {
            #print Dumper "$!";
            #select undef,undef,undef,.01;
            if ($! != EINTR && $! != 10038){
                die $!;
            }
            
            if ($timeout == -1){
                next;
            }
            
            if ($timeout == 0){
                return;
            }
            
            #Interrupted by a signal. Update timeout and poll again. */
            goto update_timeout;
        }
        
        $nevents = 0;
        assert($loop->{watchers});
        
        $loop->{snfds} = $nfds;
        
        for ( keys %{$loop->{watchers}} ) {
            
            my ($pev,$fd, $ev);
            
            # Skip invalidated events, see platform_invalidate_fd
            $w = $loop->{watchers}->{$_};
            if (!$w) {
                #File descriptor that we've stopped watching, disarm it.
                #Ignore all errors because we may be racing with another thread
                #when the file descriptor is closed.
                #epoll_ctl($loop->{backend_fd}, $EPOLL_CTL_DEL, $fd, $pe);
                Rum::Loop::IO::platform_invalidate_fd($loop,$_);
                next;
            }
            
            $fd = $w->{fd};
            $ev = $w->{pevents};
            
            if ($ev & $EPOLLIN){
                $pev |= vec($rout, $fd, 1) ? $EPOLLIN : 0;
            }
            
            if ($ev & $EPOLLOUT){
                $pev |= vec($wout, $fd, 1) ? $EPOLLOUT : 0;
            }
            
            if ($ev & $EPOLLERR){
                $pev |= vec($eout, $fd, 1) ? $EPOLLERR : 0;
            }
            
            #Give users only events they're interested in. Prevents spurious
            #callbacks when previous callback invocation in this loop has stopped
            #the current watcher. Also, filters out events that users has not
            #requested us to watch.
            
            $pev &= $w->{pevents} | $POLLERR | $POLLHUP;
            
            # Work around an epoll quirk where it sometimes reports just the
            # EPOLLERR or EPOLLHUP event. In order to force the event loop to
            # move forward, we merge in the read/write events that the watcher
            # is interested in; uv__read() and uv__write() will then deal with
            # the error or hangup in the usual fashion.
            
            # Note to self: happens when epoll reports EPOLLIN|EPOLLHUP, the user
            # reads the available data, calls uv_read_stop(), then sometime later
            # calls uv_read_start() again. By then, libuv has forgotten about the
            # hangup and the kernel won't report EPOLLIN again because there's
            # nothing left to read. If anything, libuv is to blame here. The
            # current hack is just a quick bandaid; to properly fix it, libuv
            # needs to remember the error/hangup event. We should get that for
            # free when we switch over to edge-triggered I/O.
            
            if ($pev == $EPOLLERR || $pev == $EPOLLHUP) {
                $pev |= $w->{pevents} & ($EPOLLIN | $EPOLLOUT);
            }
            
            if ($pev != 0) {
                Rum::Loop::IO::platform_invalidate_fd($loop,$fd);
                $w->{cb}->($loop, $w, $pev);
                $nevents++;
            }
            
            last if $nevents == $nfds;
        }
        
        #$loop->{watchers}->{events} = undef;
        $loop->{snfds}   = undef;
        
        if ($nevents != 0) {
            if ($nfds == $loop->{nfds} && --$count != 0) {
                #Poll for more events but don't block this time.
                $timeout = 0;
                next;
            }
            return;
        }
        
        if ($timeout == 0) {
            return;
        }
        
        if ($timeout == -1) {
            next;
        }
        
        update_timeout:{
            assert($timeout > 0);
            $diff = $loop->{time} - $base;
            if ($diff >= $timeout){
                return;
            }
            
            $timeout -= $diff;
        }
    }
}

1;

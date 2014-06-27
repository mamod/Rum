package Rum::Loop::IO::EPoll;
use strict;
use warnings;
use Data::Dumper;
use POSIX qw(:errno_h);
use Rum::Loop::Flags qw[:IO];
use Rum::Loop::Queue;
use Rum::Loop::Utils 'assert';

my $EPOLL_CTL_ADD = 1;
my $EPOLL_CTL_DEL = 2;
my $EPOLL_CTL_MOD = 3;

my $EPOLLIN         = 1;
my $EPOLLOUT        = 4;
my $EPOLLERR        = 8;
my $EPOLLHUP        = 16;
my $EPOLLONESHOT    = 0x40000000;
my $EPOLLET         = 0x80000000;

sub EPOLLIN      { $EPOLLIN      }
sub EPOLLOUT     { $EPOLLOUT     }
sub EPOLLERR     { $EPOLLERR     }
sub EPOLLHUP     { $EPOLLHUP     }
sub EPOLLONESHOT { $EPOLLONESHOT }
sub EPOLLET      { $EPOLLET      }

require 'sys/syscall.ph';

my ($SYS_epoll_create1,$SYS_epoll_create, $SYS_epoll_ctl, $SYS_epoll_wait);

$SYS_epoll_create1 = eval { &SYS_epoll_create1 }  || 0;
$SYS_epoll_create  = eval { &SYS_epoll_create }   || 0;
$SYS_epoll_ctl     = eval { &SYS_epoll_ctl }      || 0;
$SYS_epoll_wait    = eval { &SYS_epoll_wait }     || 0;

sub epoll_create1 {
    my $flag = shift;
    if ($SYS_epoll_create1) {
        return syscall($SYS_epoll_create1, 0x80000);
    }
    $! = ENOSYS;
    return -1;
}

sub epoll_create {
    my $flag = shift;
    if ($SYS_epoll_create) {
        return syscall ($SYS_epoll_create, $flag);
    }
    
    $! = ENOSYS;
    return -1;
}

##Epoll
#epoll_ctl($loop->{backend_fd}, $op, $w->{fd}, $e)
sub epoll_ctl {
    my ($epfd, $op, $fd, $events) = @_;
    
    $! = 0;
    if ($SYS_epoll_ctl) {
        return syscall($SYS_epoll_ctl, $epfd, $op, $fd, $events);
    }
    
    $! = ENOSYS;
    return -1;
}


sub epoll_wait {
    my ($epfd, $events, $nevents, $timeout) = @_;
    $! = 0;
    if ($SYS_epoll_wait) {
        return syscall($SYS_epoll_wait, $epfd, $_[1], $nevents, $timeout);
    } else {
        die;
    }
}

sub Rum::Loop::IO::platform_invalidate_fd {
    my $loop = shift;
    my $fd = shift;
    my $events = $loop->{watchers}->{events};
    my $nfds = $loop->{watchers}->{nfds};
    
    if ($events) {
        for (my $i = 0; $i < $nfds; $i++ ){
            my ($ofd) = unpack("LL", substr($$events, (12*$i)+4, 4));
            if ($ofd == $fd) {
                #substr $$events, (12*$i)+4, 4, pack("L",$fd);
                #my ($ofd) = unpack("LL", substr(${$loop->{watchers}->{events}}, (12*$i)+4, 4));
            }
        }
    }
}

sub Rum::Loop::IO::io_poll {
    my ($loop, $timeout) = @_;
    my $events = "\0" x 12 x $loop->{nfds};
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
        return;
    }
    
    while (!QUEUE_EMPTY($loop->{watcher_queue})) {
        $q = QUEUE_HEAD($loop->{watcher_queue});
        $w = $q->{data};
        QUEUE_REMOVE($q);
        QUEUE_INIT2($q, $w);
        
        assert($w->{pevents} != 0);
        assert($w->{fd} >= 0);
        assert($w->{fd} < $loop->{nwatchers});
        
        if ($w->{events} == 0){
            $op = $EPOLL_CTL_ADD;
        } else {
            $op = $EPOLL_CTL_MOD;
        }
        
        #XXX Future optimization: do EPOLL_CTL_MOD lazily if we stop watching
        #events, skip the syscall and squelch the events after epoll_wait().
        $e = pack("LLL", $w->{pevents}, $w->{fd}, 0);
        if ( epoll_ctl($loop->{backend_fd}, $op, $w->{fd}, $e) ) {
            if ( $! != EEXIST ){
                die $!;
            }
            
            assert($op == $EPOLL_CTL_ADD);
            #We've reactivated a file descriptor that's been watched before.
            if ( epoll_ctl($loop->{backend_fd}, $EPOLL_CTL_MOD, $w->{fd}, $e) ){
                die $!;
            }
            
            $w->{events} = $w->{pevents};
        }
    }
    
    
    assert($timeout >= -1);
    $base = $loop->{time};
    
    $count = 48; # Benchmarks suggest this gives the best throughput.
    
    for (;;) {
        
        my $wait = $timeout == -1 ? -1 : $timeout * 1000;
        $nfds = epoll_wait($loop->{backend_fd},
                            $events,
                            $loop->{nfds},
                            $wait);
        
        # Update loop->time unconditionally. It's tempting to skip the update when
        # timeout == 0 (i.e. non-blocking poll) but there is no guarantee that the
        # operating system didn't reschedule our process while in the syscall.
        #print Dumper $nfds;
        
        $loop->update_time();
        
        if ($nfds == 0) {
            assert($timeout != -1);
            return;
        }
        
        if ($nfds == -1) {
            if ($! != EINTR){
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
        
        $loop->{watchers}->{events}  = \$events;
        $loop->{watchers}->{nfds}    = $nfds;
        
        for ($i = 0; $i < $nfds; $i++) {
            $pe = substr($events, 12*$i, 8);
            my ($pev,$fd) = unpack("LL", $pe);
            
            # Skip invalidated events, see platform_invalidate_fd
            if ( $fd == -1 ) {
                die;
                next;
            }
            
            assert($fd >= 0);
            assert($fd < $loop->{nwatchers},$fd);
            
            $w = $loop->{watchers}->{$fd};
            
            if (!$w) {
                #File descriptor that we've stopped watching, disarm it.
                #Ignore all errors because we may be racing with another thread
                #when the file descriptor is closed.
                
                epoll_ctl($loop->{backend_fd}, $EPOLL_CTL_DEL, $fd, $pe);
                next;
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
                $w->{cb}->($loop, $w, $pev);
                $nevents++;
            }
            
            #$events = $loop->{events};
            #last;
        }
        
        $loop->{watchers}->{events} = undef;
        $loop->{watchers}->{nfds}   = undef;
        
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

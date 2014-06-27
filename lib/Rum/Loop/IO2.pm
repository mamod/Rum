package Rum::Loop::IO2;
use strict;
use warnings;
use Rum::Loop::Queue;
use Rum::Loop::Flags qw($POLLIN $POLLOUT :Event);
use Rum::Loop::Utils 'assert';
use Data::Dumper;

my $INT_MAX = 2048;

use base qw/Exporter/;
our @EXPORT = qw (
    io_init
    io_start
    io_stop
    io_close
    io_poll
    io_active
    io_feed
);

## io_poll will be defined in one of the detected available backends
## Rum::Loop::IO::KQueue
## Rum::Loop::IO::EPoll
## Rum::Loop::IO::Poll

sub next_power_of_two {
    my $val = shift;
    $val -= 1;
    $val |= $val >> 1;
    $val |= $val >> 2;
    $val |= $val >> 4;
    $val |= $val >> 8;
    $val |= $val >> 16;
    $val += 1;
    return $val;
}

sub maybe_resize {
    my ($loop, $len) = @_;
    my $watchers;
    my $nwatchers;
    my $i = 0;
    
    return if ($len <= $loop->{nwatchers});
    $nwatchers = next_power_of_two($len);
    # ==== no really this should be removed
    #for ($i = $loop->{nwatchers}; $i < $nwatchers; $i++) {
    #    $loop->{watchers}->{$i} = undef;
    #}
    #$loop->{watchers} = $watchers;
    # ======================================
    $loop->{nwatchers} = $nwatchers;
}

sub io_init {
    my ($w, $cb, $fh) = @_;
    my $fd = ref $fh ? fileno $fh : $fh;
    assert($cb,"Must provide a callback function");
    assert ($fd >= -1,"$fd is not a valid file descriptor");
    $w->{pending_queue} = Rum::Loop::Queue->new($w);
    $w->{watcher_queue} = Rum::Loop::Queue->new($w);
    $w->{cb} = $cb;
    $w->{fd} = $fd;
    $w->{fh} = $fh;
    $w->{events}  = 0;
    $w->{pevents} = 0;
    if ($KQUEUE) {
        $w->{rcount} = 0;
        $w->{wcount} = 0;
    }
}

sub io_start {
    my ($loop, $w, $events) = @_;
    assert(0 == ($events & ~($POLLIN | $POLLOUT)));
    assert(0 != $events);
    assert($w->{fd} >= 0);
    assert($w->{fd} < $INT_MAX);
    
    $w->{pevents} |= $events;
    maybe_resize($loop, $w->{fd} + 1);
    #$loop->{nwatchers} = $w->{fd} + 1;
    ##if !defined(__sun)
        # The event ports backend needs to rearm all file descriptors on each and
        # every tick of the event loop but the other backends allow us to
        # short-circuit here if the event mask is unchanged.
        if ($w->{events} == $w->{pevents}) {
            if ( $w->{events} == 0 && !$w->{watcher_queue}->empty() ) {
                $w->{watcher_queue}->remove();
                $w->{watcher_queue} = Rum::Loop::Queue->new($w);
            }
            return;
        }
    ##endif
    
    if ($w->{watcher_queue}->empty()) {
        $loop->{watcher_queue}->insert_tail($w->{watcher_queue});
    }
    
    if (!$loop->{watchers}->{$w->{fd}}) {
        $loop->{watchers}->{$w->{fd}} = $w;
        $loop->{nfds}++;
    }
}

sub io_stop {
    my ($loop, $w, $events) = @_;
    assert(0 == ($events & ~($POLLIN | $POLLOUT)));
    assert(0 != $events);
    
    if ($w->{fd} == -1) {
        return;
    }
    
    assert($w->{fd} >= 0);
    
    #/* Happens when uv__io_stop() is called on a handle that was never started. */
    if ($w->{fd} >= $loop->{nwatchers}) {
        return;
    }
    
    $w->{pevents} &= ~$events;
    
    if ($w->{pevents} == 0) {
        $w->{watcher_queue}->remove();
        $w->{watcher_queue} = Rum::Loop::Queue->new($w);
        
        if ($loop->{watchers}->{$w->{fd}}) {
            assert($loop->{watchers}->{$w->{fd}} eq $w);
            assert($loop->{nfds} > 0);
            undef $loop->{watchers}->{$w->{fd}};
            $loop->{nfds}--;
            $w->{events} = 0;
        }
    } elsif ($w->{watcher_queue}->empty) {
        $loop->{watcher_queue}->insert_tail($w->{watcher_queue});
    }
}

sub io_close {
    my ($loop, $w) = @_;
    io_stop($loop, $w, $POLLIN | $POLLOUT);
    $w->{pending_queue}->remove();
}

sub io_active {
    my ($w, $events) = @_;
    assert(0 == ($events & ~($POLLIN | $POLLOUT)));
    assert(0 != $events);
    return 0 != ($w->{pevents} & $events);
}

sub io_feed {
    my ($loop, $w) = @_;
    if ( $w->{pending_queue}->empty() ) {
        $loop->{pending_queue}->insert_tail( $w->{pending_queue} );
    }
}

1;

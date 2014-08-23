package Rum::Loop::IO;
use strict;
use warnings;
use Data::Dumper;
use Rum::Loop::Queue;

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

use Rum::Loop::Flags qw($POLLIN $POLLOUT :Event);
use Rum::Loop::Utils 'assert';

sub io_init {
    my ($loop, $handle, $fh, $cb);
    if (@_ == 4) {
        ($loop, $handle, $fh, $cb) = @_;
        my $fd = fileno $fh || -1;
        $_[1]->{fh} = $fh;
        $_[1]->{fd} = $fd;
        $_[1]->{cb} = $cb;
        $_[1]->{events} = 0;
        $_[1]->{pevents} = 0;
        $_[1]->{pending_queue} = QUEUE_INIT($_[1]);
        $_[1]->{watcher_queue} = QUEUE_INIT($_[1]);
        return 1;
    } else {
        ($loop, $fh, $cb) = @_;
        $handle = {};
    }
    
    my $fd = fileno $fh || -1;
    $handle->{fh} = $fh;
    $handle->{fd} = $fd;
    $handle->{cb} = $cb;
    $handle->{events} = 0;
    $handle->{pevents} = 0;
    
    $handle->{pending_queue} = QUEUE_INIT($handle);
    $handle->{watcher_queue} = QUEUE_INIT($handle);
    return $handle;
}

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
    $loop->{nwatchers} = $nwatchers;
}


sub io_start {
    my ($loop, $w, $events) = @_;
    assert(0 == ($events & ~($POLLIN | $POLLOUT)));
    assert(0 != $events);
    assert($w->{fd} >= 0);
    #assert(w->fd < INT_MAX);
    
    $w->{pevents} |= $events;
    maybe_resize($loop, $w->{fd} + 1);
    
    ##if !defined(__sun)
    # The event ports backend needs to rearm all file descriptors on each and
    # every tick of the event loop but the other backends allow us to
    # short-circuit here if the event mask is unchanged.
    if ($w->{events} == $w->{pevents}) {
        if ($w->{events} == 0 && !QUEUE_EMPTY($w->{watcher_queue})) {
            QUEUE_REMOVE($w->{watcher_queue});
            QUEUE_INIT2($w->{watcher_queue},$w);
        }
        return;
    }
    
    if ( QUEUE_EMPTY( $w->{watcher_queue} ) ){
        QUEUE_INSERT_TAIL($loop->{watcher_queue}, $w->{watcher_queue});
    }
    
    if ( !$loop->{watchers}->{ $w->{fd} } ) {
        $loop->{watchers}->{$w->{fd}} = $w;
        $loop->{nfds}++;
    }
}

sub io_stop {
    my ($loop, $w, $events) = @_;
    
    assert( 0 == ( $events & ~($POLLIN | $POLLOUT) ) );
    assert(0 != $events);
    
    if ($w->{fd} == -1 || !$w->{fh}){
        return;
    }
    
    assert($w->{fd} >= 0);
    
    #Happens when io_stop() is called on a handle that was never started.
    if ( $w->{fd} >= $loop->{nwatchers} ){
        return;
    }
    
    $w->{pevents} &= ~$events;
    
    if ($w->{pevents} == 0) {
        QUEUE_REMOVE($w->{watcher_queue});
        QUEUE_INIT2($w->{watcher_queue},$w);
        
        if ($loop->{watchers}->{$w->{fd}}) {
            assert($loop->{watchers}->{$w->{fd}} == $w);
            assert($loop->{nfds} > 0);
            delete $loop->{watchers}->{$w->{fd}};
            $loop->{nfds}--;
            $w->{events} = 0;
        }
    } elsif (QUEUE_EMPTY($w->{watcher_queue})){
        QUEUE_INSERT_TAIL($loop->{watcher_queue}, $w->{watcher_queue});
    }
}

sub io_close {
    my ($loop, $w) = @_;
    io_stop($loop, $w, $POLLIN | $POLLOUT);
    platform_invalidate_fd($loop, $w->{fd}, $w->{events});
    QUEUE_REMOVE($w->{pending_queue});
}

sub io_active {
    my ($loop, $w, $events) = @_;
    assert(0 == ($events & ~($POLLIN | $POLLOUT)));
    assert(0 != $events);
    return 0 != ($w->{pevents} & $events);
}

sub io_feed {
    my ($loop, $w) = @_;
    if ( QUEUE_EMPTY($w->{pending_queue}) ) {
        QUEUE_INSERT_TAIL($loop->{pending_queue}, $w->{pending_queue} );
    }
}

1;

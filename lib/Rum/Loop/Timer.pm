package Rum::Loop::Timer;
use strict;
use warnings;

use base qw/Exporter/;
our @EXPORT = qw (
    timer_init
    next_timeout
    timer_start
    run_timers
    timer_stop
    timer_again
    timer_close
    timer_get_repeat
    timer_set_repeat
);

my $INT_MAX = 1000;

sub timer_init {
    my ($loop, $handle) = @_;
    my $ret = $loop->handle_init($handle, 'TIMER');
    $handle->{wrap} = $handle;
    $handle->{timer_cb} = undef;
    $handle->{repeat} = 0;
    #bless $handle, __PACKAGE__;
    return $ret;
}

sub timer_start {
    my ($loop,$handle,$cb,$timeout,$repeat) = @_;
    if ( Rum::Loop::is_active($handle) ) {
        $loop->timer_stop($handle);
    }
    
    my $clamped_timeout = $loop->{time} + $timeout;
    $clamped_timeout = -1 if $clamped_timeout < $timeout;
    
    $handle->{timer_cb} = $cb;
    $handle->{timeout} = $clamped_timeout;
    $handle->{repeat} = $repeat;
    
    # start_id is the second index to be compared in timer_cmp()
    $handle->{start_id} = $loop->{timer_counter}++;
    $loop->{timer_handles}->insert($handle);
    $loop->handle_start($handle);
    return 0;
}

sub run_timers {
    my $loop = shift;
    while ( my $handle = $loop->{timer_handles}->min() ){
        if ( $handle->{timeout} > $loop->{time} ) {
            return;
        }
        
        $loop->timer_stop($handle);
        $loop->timer_again($handle);
        $handle->{timer_cb}->($handle, 0);
    }
}

*timer_close = \&timer_stop;
sub timer_stop {
    my $loop = shift;
    my $handle = shift;
    if (!Rum::Loop::is_active($handle)) {
        return 0;
    }
    
    $loop->{timer_handles}->remove($handle);
    $loop->handle_stop($handle);
    return 0;
}

sub timer_again {
    my ($loop,$handle) = @_;
    die "the timer has never been started before" if !$handle->{timer_cb};
    
    if ($handle->{repeat}) {
        $loop->timer_stop($handle);
        $loop->timer_start($handle, $handle->{timer_cb}, $handle->{repeat}, $handle->{repeat});
    }
    
    return 0;
}

sub next_timeout {
    my $loop = shift;
    
    #/* RB_MIN expects a non-const tree root. That's okay, it doesn't modify it. */
    my $handle = $loop->{timer_handles}->min();

    if (!$handle){
        return -1; #block indifinetly
    }

    if ($handle->{timeout} <= $loop->{time} ){
        return 0;
    }
    
    my $diff = $handle->{timeout} - $loop->{time};
    if ($diff > $INT_MAX) {
        $diff = $INT_MAX;
    }
    
    return $diff/1000;
}

sub timer_get_repeat {
    my $handle = shift;
    return $handle->{repeat};
}

sub timer_set_repeat {
    my ($handle, $repeat) = @_;
    $handle->{repeat} = $repeat;
}

1;

__END__

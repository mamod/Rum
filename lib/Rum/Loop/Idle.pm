package Rum::Loop::Idle;
use Rum::Loop::Handle ();
use strict;
use warnings;
use Rum::Loop::Queue;
use base qw/Exporter/;
our @EXPORT = qw (
    idle_init
    idle_start
    idle_stop
    idle_close
    run_idle
);

sub idle_init {
    my ($loop, $handle) = @_;
    my $ret = $loop->handle_init($handle, 'CHECK');
    return $ret;
}

sub idle_start {
    my ($loop,$handle, $cb) = @_;
    return 0 if (Rum::Loop::Handle::is_active($handle));
    die "callback is required" if (!$cb);# return -EINVAL;
    $handle->{queue} = QUEUE_INIT($handle);
    QUEUE_INSERT_HEAD($loop->{idle_handles}, $handle->{queue});
    $handle->{idle_cb} = $cb;
    $loop->handle_start($handle);
    return 0;
}

*idle_close = *idle_stop;
sub idle_stop {
    my ($loop,$handle) = @_;
    return 0 if (!Rum::Loop::Handle::is_active($handle));
    QUEUE_REMOVE($handle->{queue});
    $loop->handle_stop($handle);
    return 0;
}

use Data::Dumper;
sub run_idle {
    my $loop = shift;
    
    QUEUE_FOREACH($loop->{idle_handles}, sub {
        my $h = $_->{data};
        $h->{idle_cb}->($h,0);
    });
    
    #$loop->{idle_handles}->foreach(sub{
    #    my $h = shift->data;
    #    $h->{idle_cb}->($h,0);
    #});
}

1;

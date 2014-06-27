package Rum::Loop::Check;
use Rum::Loop::Handle ();
use strict;
use warnings;
use Rum::Loop::Queue;
use base qw/Exporter/;
our @EXPORT = qw (
    check_init
    check_start
    check_stop
    check_close
    run_check
);

sub check_init {
    my ($loop, $handle) = @_;
    my $ret = $loop->handle_init($handle, 'CHECK');
    return $ret;
}

sub check_start {
    my ($loop, $handle, $cb) = @_;
    return 0 if (Rum::Loop::Handle::is_active($handle));
    die "callback is required" if (!$cb);# return -EINVAL;
    $handle->{queue} = QUEUE_INIT($handle);
    QUEUE_INSERT_HEAD($loop->{check_handles}, $handle->{queue});
    $handle->{check_cb} = $cb;
    $loop->handle_start($handle);
    return 0;
}

*check_close = *check_stop;
sub check_stop {
    my ($loop, $handle) = @_;
    return 0 if (!Rum::Loop::Handle::is_active($handle));
    QUEUE_REMOVE($handle->{queue});
    $loop->handle_stop($handle);
    return 0;
}

sub run_check {
    my $loop = shift;
    return if QUEUE_EMPTY($loop->{check_handles});
    
    QUEUE_FOREACH($loop->{check_handles}, sub {
        my $h = $_->{data};
        $h->{check_cb}->($h,0);
    });
}

1;

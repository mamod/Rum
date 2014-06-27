package Rum::Loop::Prepare;
use Rum::Loop::Handle ();
use strict;
use warnings;
use Rum::Loop::Queue;
use base qw/Exporter/;
our @EXPORT = qw (
    prepare_init
    prepare_start
    prepare_stop
    prepare_close
    run_prepare
);

sub prepare_init {
    my ($loop, $handle) = @_;
    my $ret = $loop->handle_init($handle, 'PREPARE');
    return $ret;
}

sub prepare_start {
    my ($loop, $handle, $cb) = @_;
    return 0 if (Rum::Loop::Handle::is_active($handle));
    die "callback is required" if (!$cb);# return -EINVAL;
    $handle->{queue} = QUEUE_INIT($handle);
    QUEUE_INSERT_HEAD($loop->{prepare_handles}, $handle->{queue});
    $handle->{prepare_cb} = $cb;
    $loop->handle_start($handle);
    return 0;
}

*prepare_close = *prepare_stop;
sub prepare_stop {
    my ($loop, $handle) = @_;
    return 0 if (!Rum::Loop::Handle::is_active($handle));
    QUEUE_REMOVE($handle->{queue});
    $loop->handle_stop($handle);
    return 0;
}

sub run_prepare {
    
    my $loop = shift;
    return if QUEUE_EMPTY($loop->{prepare_handles});
    
    QUEUE_FOREACH($loop->{prepare_handles}, sub {
        my $h = $_->{data};
        $h->{prepare_cb}->($h,0);
    });
}

1;

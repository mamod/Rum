package Rum::Wrap::Timers;
use strict;
use warnings;
use lib '../../';
use Rum::Loop ();
use Rum::RBTree;
my $timer_counter = 0;
my $tree;
use Data::Dumper;

my $loop = Rum::Loop::default_loop();
use Rum::Wrap::Handle qw(close ref unref);

sub timer_cmp {
    my ($a,$b) = @_;
    return -1 if ($a->{timeout} < $b->{timeout});
    return  1 if ($a->{timeout} > $b->{timeout});
    #compare start_id when both has the same timeout
    return -1 if ($a->{start_id} < $b->{start_id});
    return  1 if ($a->{start_id} > $b->{start_id});
    return 0;
}

sub new {
    my $handle_ = {};
    my $this = bless {}, shift;
    $loop->timer_init($handle_);
    Rum::Wrap::Handle::HandleWrap($this,$handle_);
    return $this;
}

sub OnTimeout {
    my ($handle, $status) = @_;
    my $wrap = $handle->{data};
    Rum::Timers::MakeCallback($wrap,'ontimeout');
}

sub start {
    my ($this,$timeout,$repeat) = @_;
    my $handle = $this->{handle__};
    $loop->timer_start($handle,\&OnTimeout, $timeout, $repeat);
}

sub run_timers {
    $loop->run();
}

sub now {
    $loop->update_time();
    return $loop->{time};
}

1;

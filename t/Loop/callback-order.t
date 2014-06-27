use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Test::More;

my $idle_cb_called = 0;
my $timer_cb_called = 0;

my $idle_handle = {};
my $timer_handle = {};
my $loop = Rum::Loop::default_loop();

#idle_cb should run before timer_cb 
sub idle_cb {
    my ($handle, $status) = @_;
    ok($idle_cb_called == 0);
    ok($timer_cb_called == 0);
    $loop->idle_stop($handle);
    $idle_cb_called++;
}

sub timer_cb {
    my ($handle, $status) = @_;
    ok($idle_cb_called == 1);
    ok($timer_cb_called == 0);
    $loop->timer_stop($handle);
    $timer_cb_called++;
}

sub next_tick {
    my ($handle, $status) = @_;
    
    $loop->idle_stop($handle);
    $loop->idle_init($idle_handle);
    $loop->idle_start($idle_handle, \&idle_cb);
    $loop->timer_init($timer_handle);
    ##FIXME I needed to raise 0 timeout
    ##in order for this test to pass
    #$timer_handle->timer_start(\&timer_cb, 0, 0);
    $loop->timer_start($timer_handle,\&timer_cb, 5, 0);
}

{

    my $idle = {};
    
    $loop->idle_init($idle);
    $loop->idle_start($idle, \&next_tick);

    ok($idle_cb_called == 0);
    ok($timer_cb_called == 0);

    $loop->run(RUN_DEFAULT);

    ok($idle_cb_called == 1);
    ok($timer_cb_called == 1);
}

done_testing();

1;

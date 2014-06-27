use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Test::More;

my $check_cb_called = 0;
my $timer_cb_called = 0;
my $close_cb_called = 0;

my $check_handle = {};
my $timer_handle1 = {};
my $timer_handle2 = {};

my $loop = Rum::Loop::default_loop();

sub close_cb {
    my $handle = shift;
    ok($handle);
    $close_cb_called++;
}

#check_cb should run before any close_cb
sub check_cb {
    my ($handle, $status) = @_;
    ok($check_cb_called == 0);
    ok($timer_cb_called == 1);
    ok($close_cb_called == 0);
    $loop->close($handle, \&close_cb);
    $loop->close($timer_handle2, \&close_cb);
    $check_cb_called++;
}

sub timer_cb {
    my ($handle, $status) = @_;
    $loop->close($handle, \&close_cb);
    $timer_cb_called++;
}

{
    

    $loop->check_init($check_handle);
    $loop->check_start($check_handle, \&check_cb);
    $loop->timer_init($timer_handle1);
    $loop->timer_start($timer_handle1, \&timer_cb, 0, 0);
    $loop->timer_init($timer_handle2);
    $loop->timer_start($timer_handle2, \&timer_cb, 100000, 0);

    ok($check_cb_called == 0);
    ok($close_cb_called == 0);
    ok($timer_cb_called == 0);

    $loop->run(RUN_DEFAULT);

    ok($check_cb_called == 1);
    ok($close_cb_called == 3);
    ok($timer_cb_called == 1);
}

done_testing();

1;

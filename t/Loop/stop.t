use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Test::More;

my $loop = Rum::Loop::default_loop();

my $prepare_handle = {};
my $timer_handle = {};
my $prepare_called = 0;
my $timer_called = 0;
my $num_ticks = 10;

sub prepare_cb {
    my ($handle, $status) = @_;
    is($handle, $prepare_handle);
    ok($status == 0);
    $prepare_called++;
    if ($prepare_called == $num_ticks) {
        $loop->prepare_stop($handle);
    }
}

sub timer_cb {
    my ($handle,$status) = @_;
    is($handle, $timer_handle);
    ok($status == 0);
    $timer_called++;
    if ($timer_called == 1) {
        $loop->stop();
    } elsif ($timer_called == $num_ticks) {
        $loop->timer_stop($handle);
    }
}

#TEST_IMPL(loop_stop)
{
    my $r;
    Rum::Loop::prepare_init(Rum::Loop::default_loop(), $prepare_handle);
    Rum::Loop::prepare_start(Rum::Loop::default_loop(), $prepare_handle, \&prepare_cb);
    Rum::Loop::timer_init(Rum::Loop::default_loop(), $timer_handle);
    Rum::Loop::timer_start(Rum::Loop::default_loop(), $timer_handle, \&timer_cb, 100, 100);
    
    $r = Rum::Loop::run(Rum::Loop::default_loop(), RUN_DEFAULT);
    ok($r != 0);
    ok($timer_called == 1);
    
    $r = Rum::Loop::run(Rum::Loop::default_loop(), RUN_NOWAIT);
    ok($r != 0);
    ok($prepare_called > 1);
    
    $r = Rum::Loop::run(Rum::Loop::default_loop(), RUN_DEFAULT);
    ok($r == 0);
    ok($timer_called == 10);
    ok($prepare_called == 10);
}

done_testing();

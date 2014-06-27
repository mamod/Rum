use lib './lib';

use warnings;
use strict;
use POSIX 'floor';
use Rum::Loop;
use Test::More;

my $IDLE_COUNT = 7;
my $ITERATIONS = 21;
my $TIMEOUT = 100;

my $prepare_1_handle = {};
my $prepare_2_handle = {};

my $check_handle = {};;

my $idle_1_handles = [];
my $idle_2_handle = {};

my $timer_handle  = {};

my $loop_iteration = 0;

my $prepare_1_cb_called = 0;
my $prepare_1_close_cb_called = 0;

my $prepare_2_cb_called = 0;
my $prepare_2_close_cb_called = 0;

my $check_cb_called = 0;
my $check_close_cb_called = 0;

my $idle_1_cb_called = 0;
my $idle_1_close_cb_called = 0;
my $idles_1_active = 0;

my $idle_2_cb_called = 0;
my $idle_2_close_cb_called = 0;
my $idle_2_cb_started = 0;
my $idle_2_is_active = 0;

my $loop = Rum::Loop::default_loop();

sub timer_cb {
    my ($handle, $status) = @_;
    is($handle, $timer_handle);
    ok($status == 0);
}


sub idle_2_close_cb {
    my ($handle) = @_;
    #diag("IDLE_2_CLOSE_CB\n");
    is($handle, $idle_2_handle);
    ok($idle_2_is_active);
    $idle_2_close_cb_called++;
    $idle_2_is_active = 0;
}

sub idle_2_cb {
    my ($handle, $status) = @_;
    
    is($handle, $idle_2_handle);
    ok($status == 0);
    
    $idle_2_cb_called++;
    
    $loop->close($handle, \&idle_2_close_cb);
}

sub idle_1_cb {
    my ($handle, $status) = @_;
    my $r;
    
    ok($handle);
    ok($status == 0);
    
    ok($idles_1_active > 0);
    
    # Init idle_2 and make it active
    if (!$idle_2_is_active && !Rum::Loop::is_closing($idle_2_handle)) {
        $loop->idle_init($idle_2_handle);
        $loop->idle_start($idle_2_handle, \&idle_2_cb);
        $idle_2_is_active = 1;
        $idle_2_cb_started++;
    }
    
    $idle_1_cb_called++;
    
    if ($idle_1_cb_called % 5 == 0) {
        $r = $loop->idle_stop($handle);
        ok($r == 0);
        $idles_1_active--;
    }
}


sub idle_1_close_cb {
    my $handle = shift;
    #print("IDLE_1_CLOSE_CB\n");
    ok($handle);
    $idle_1_close_cb_called++;
}

sub prepare_1_close_cb {
    my $handle = shift;
    #print("PREPARE_1_CLOSE_CB");
    is($handle, $prepare_1_handle);
    $prepare_1_close_cb_called++;
}

sub check_close_cb {
    my $handle = shift;
    #print("CHECK_CLOSE_CB\n");
    is($handle,$check_handle);
    $check_close_cb_called++;
}

sub prepare_2_close_cb {
    my $handle = shift;
    #print("PREPARE_2_CLOSE_CB\n");
    is($handle , $prepare_2_handle);
    $prepare_2_close_cb_called++;
}


sub check_cb {
    my ($handle, $status) = @_;
    my $i = 0;
    my $r;
    
    #print("CHECK_CB\n");
    
    is($handle,$check_handle);
    ok($status == 0);
    
    if ($loop_iteration < $ITERATIONS) {
        # Make some idle watchers active
        for ($i = 0; $i < 1 + ($loop_iteration % $IDLE_COUNT); $i++) {
            $loop->idle_start($idle_1_handles->[$i], \&idle_1_cb);
            $idles_1_active++;
        }
    } else {
        # End of the test - close all handles
        $loop->close($prepare_1_handle, \&prepare_1_close_cb);
        $loop->close($check_handle, \&check_close_cb);
        $loop->close($prepare_2_handle, \&prepare_2_close_cb);
        
        for ($i = 0; $i < $IDLE_COUNT; $i++) {
            $loop->close($idle_1_handles->[$i], \&idle_1_close_cb);
        }
        
        # This handle is closed/recreated every time, close it only if it is
        # active.
        if ($idle_2_is_active) {
            $loop->close($idle_2_handle, \&idle_2_close_cb);
        }
    }

    $check_cb_called++;
}


sub prepare_2_cb {
    my ($handle, $status) = @_;
    my $r;
    
    print("PREPARE_2_CB\n");
    
    is($handle, $prepare_2_handle);
    ok($status == 0);
    
    # prepare_2 gets started by prepare_1 when (loop_iteration % 2 == 0),
    # and it stops itself immediately. A started watcher is not queued
    # until the next round, so when this callback is made
    # (loop_iteration % 2 == 0) cannot be true.
    ok($loop_iteration % 2 != 0);
    
    $r = $loop->prepare_stop($handle);
    ok($r == 0);
    $prepare_2_cb_called++;
}

sub prepare_1_cb {
    my ($handle, $status) = @_;
    my $r;
    
    #print("PREPARE_1_CB\n");
    
    is($handle, $prepare_1_handle);
    ok($status == 0);
    
    if ($loop_iteration % 2 == 0) {
        $r = $loop->prepare_start($prepare_2_handle, \&prepare_2_cb);
        ok($r == 0);
    }
    
    $prepare_1_cb_called++;
    $loop_iteration++;
    
    #printf("Loop iteration %d of %d.\n", $loop_iteration, $ITERATIONS);
}

#TEST_IMPL(loop_handles) 
{
    my $i;
    my $r;
    
    $loop->prepare_init($prepare_1_handle);
    Rum::Loop::prepare_start($loop, $prepare_1_handle, \&prepare_1_cb);
    
    $loop->check_init($check_handle);

    Rum::Loop::check_start($loop, $check_handle, \&check_cb);
    
    # initialize only, prepare_2 is started by prepare_1_cb */
    $loop->prepare_init($prepare_2_handle);
    
    for ($i = 0; $i < $IDLE_COUNT; $i++) {
        # initialize only, idle_1 handles are started by check_cb */
        $idle_1_handles->[$i] = {};
        $loop->idle_init($idle_1_handles->[$i]);
    }
    
    # don't init or start idle_2, both is done by idle_1_cb */
    
    # the timer callback is there to keep the event loop polling */
    # unref it as it is not supposed to keep the loop alive */
    $loop->timer_init($timer_handle);
    $loop->timer_start($timer_handle, \&timer_cb, $TIMEOUT, $TIMEOUT);
    $loop->unref($timer_handle);
    
    $r = $loop->run();
    
    is($loop_iteration, $ITERATIONS);
    
    is($prepare_1_cb_called, $ITERATIONS);
    is($prepare_1_close_cb_called, 1);
    
    is($prepare_2_cb_called, floor($ITERATIONS / 2.0));
    is($prepare_2_close_cb_called, 1);
    
    is($check_cb_called, $ITERATIONS);
    is($check_close_cb_called, 1);
    
    # idle_1_cb should be called a lot
    is($idle_1_close_cb_called, $IDLE_COUNT);
    
    is($idle_2_close_cb_called, $idle_2_cb_started);
    is($idle_2_is_active, 0);
    
}


done_testing();

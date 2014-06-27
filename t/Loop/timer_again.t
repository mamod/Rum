use Test::More;
use lib './lib';
use Rum::Loop;

my $close_cb_called = 0;
my $repeat_1_cb_called = 0;
my $repeat_2_cb_called = 0;
my $repeat_2_cb_allowed = 0;

sub close_cb {
    my $handle = shift;
    ok($handle);
    $close_cb_called++;
}


my $loop = Rum::Loop->new();

my $dummy = {};
my $repeat_1 = {};
my $repeat_2 = {};

sub repeat_1_cb {
    my ($handle, $status) = @_;
    my $r;

    is($handle, $repeat_1);
    ok($status == 0);

    is(Rum::Loop::timer_get_repeat($handle), 50);

    $repeat_1_cb_called++;

    $loop->timer_again($repeat_2);

    if ($repeat_1_cb_called == 10) {
        $loop->close($handle, \&close_cb);
        #/* We're not calling uv_timer_again on repeat_2 any more, so after this */
        #/* timer_2_cb is expected. */
        $repeat_2_cb_allowed = 1;
        return;
    }
}


sub repeat_2_cb {
    my ($handle, $status) = @_;
    ok($handle == $repeat_2);
    ok($status == 0);
    ok($repeat_2_cb_allowed);

    $repeat_2_cb_called++;

    if (Rum::Loop::timer_get_repeat($repeat_2) == 0) {
        ok(0 == Rum::Loop::is_active($handle) );
        $loop->close($handle, \&close_cb);
        return;
    }

    #LOGF("uv_timer_get_repeat %ld ms\n",
    #  (long int)uv_timer_get_repeat(&repeat_2));
  
    ok(Rum::Loop::timer_get_repeat($repeat_2) == 100);

    #/* This shouldn't take effect immediately. */
    Rum::Loop::timer_set_repeat($repeat_2, 0);
}


{
    my $r;
    my $start_time = Rum::Loop::now($loop);
    ok(0 < $start_time);

    # Verify that it is not possible to uv_timer_again a never-started timer. */
    $loop->timer_init($dummy);
    
    #dies
    #$loop->timer_again($dummy);
    #ASSERT(r == UV_EINVAL);
    
    $loop->unref($dummy);

    # Start timer repeat_1.
    $loop->timer_init($repeat_1);
    $loop->timer_start($repeat_1, \&repeat_1_cb, 50, 0);
    
    is(Rum::Loop::timer_get_repeat($repeat_1), 0);
    
    # Actually make repeat_1 repeating.
    Rum::Loop::timer_set_repeat($repeat_1, 50);
    is(Rum::Loop::timer_get_repeat($repeat_1), 50);
    
    # Start another repeating timer. It'll be again()ed by the repeat_1 so
    # it should not time out until repeat_1 stops.
    
    $loop->timer_init($repeat_2);
    $r = $loop->timer_start($repeat_2, \&repeat_2_cb, 100, 100);

    is(Rum::Loop::timer_get_repeat($repeat_2), 100);
    
    $loop->run($Rum::Loop::RUN_DEFAULT);
    
    is($repeat_1_cb_called, 10);
    is($repeat_2_cb_called, 2);
    is($close_cb_called, 2);
    
    my $now = $loop->now() - $start_time;
    #diag "Test took $now ms (expected ~700 ms)";
    printf STDERR ("Test took %ld ms (expected ~700 ms)\n",
       $loop->now() - $start_time);
    
}

done_testing();

1;



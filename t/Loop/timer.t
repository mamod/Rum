use lib './lib';
use Rum::Loop;
use Test::More;

my $once_cb_called = 0;
my $once_close_cb_called = 0;
my $repeat_cb_called = 0;
my $repeat_close_cb_called = 0;
my $order_cb_called = 0;
my $start_time;

my $tiny_timer = {};
my $huge_timer1 = {};
my $huge_timer2 = {};

my $loop = Rum::Loop::main_loop();

sub once_close_cb {
    my $handle = shift;
    printf("ONCE_CLOSE_CB\n");

    ok($handle);
    ok(!Rum::Loop::is_active($handle));
    $once_close_cb_called++;
}

sub once_cb {
    my ($handle,$status) = @_;
    printf("ONCE_CB %d\n", $once_cb_called);

    ok($handle);
    is($status,0);
    ok(0 == Rum::Loop::is_active($handle));

    $once_cb_called++;

    $loop->close($handle, \&once_close_cb);
    #/* Just call this randomly for the code coverage. */
    $loop->update_time();
}

sub repeat_close_cb {
    my $handle = shift;
    printf("REPEAT_CLOSE_CB\n");
    ok($handle);
    $repeat_close_cb_called++;
}
use Data::Dumper;
sub repeat_cb {
    my ($handle, $status) = @_;
    printf("REPEAT_CB\n");

    ok($handle);
    is($status, 0);
    is(Rum::Loop::is_active($handle), 1);
    
    $repeat_cb_called++;
    
    if ($repeat_cb_called == 5) {
        $loop->close($handle, \&repeat_close_cb);
    }
}


sub never_cb {
    fail("never_cb should never be called");
}

#timer
{
    my @once_timers;
    my $once = {};
    my $repeat = {};
    my $never = {};
    my $i;
    my $r;
  
    my $start_time = $loop->now();
    ok(0 < $start_time);
  
    #/* Let 10 timers time out in 500 ms total. */
    for ($i = 0; $i < 10; $i++) {
        $once = $once_timers[$i] = {};
        $loop->timer_init($once);
        $loop->timer_start($once, \&once_cb, $i * 50, 0);
    }
    
    #/* The 11th timer is a repeating timer that runs 4 times */
    $loop->timer_init($repeat);
    $loop->timer_start($repeat, \&repeat_cb, 100, 100);
    
    #/* The 12th timer should not do anything. */
    $loop->timer_init($never);
    $loop->timer_start($never, \&never_cb, 100, 100);
    $loop->timer_stop($never);
    $loop->unref($never);
    
    $loop->run($Rum::Loop::RUN_DEFAULT);
    
    is($once_cb_called, 10);
    is($once_close_cb_called, 10);
    printf("repeat_cb_called %d\n", $repeat_cb_called);
    is($repeat_cb_called, 5);
    is($repeat_close_cb_called, 1);
  
    ok(500 <= $loop->now() - $start_time);
}



#TEST_IMPL(timer_start_twice)
{
    my $once = {};
    my $r;
    $once_cb_called = 0;
    $loop->timer_init($once);
    $loop->timer_start($once, \&never_cb, 86400 * 1000, 0);
    
    $loop->timer_start($once, \&once_cb, 10, 0);

    Rum::Loop::run($loop, $Rum::Loop::RUN_DEFAULT);

    is($once_cb_called, 1);
}


#TEST_IMPL(timer_init)
{
  my $handle = {};
    
    $loop->timer_init($handle);
    ok(0 == Rum::Loop::timer_get_repeat($handle));
    ok(0 == Rum::Loop::is_active($handle));
}



sub order_cb_a {
    my ($handle, $status) = @_;
    ok($order_cb_called++ == $handle->{data});
}


sub order_cb_b {
    my ($handle, $status) = @_;
    ok($order_cb_called++ == $handle->{data});
}


#TEST_IMPL(timer_order)
{
    my $first = 0;
    my $second = 1;
    my $handle_a = {};
    my $handle_b = {};
    
    $loop->timer_init($handle_a);
    $loop->timer_init($handle_b);
  
    #/* Test for starting handle_a then handle_b */
    $handle_a->{data} = $first;
    $loop->timer_start($handle_a, \&order_cb_a, 0, 0);
    $handle_b->{data} = $second;
    $loop->timer_start($handle_b, \&order_cb_b, 0, 0);
    $loop->run($Rum::Loop::RUN_DEFAULT);
  
    is($order_cb_called, 2);
  
    $loop->timer_stop($handle_a);
    $loop->timer_stop($handle_b);
  
    #/* Test for starting handle_b then handle_a */
    $order_cb_called = 0;
    $handle_b->{data} = $first;
    $loop->timer_start($handle_b, \&order_cb_b, 0, 0);
    
    $handle_a->{data} = $second;
    $loop->timer_start($handle_a, \&order_cb_a, 0, 0);
    $loop->run($Rum::Loop::RUN_DEFAULT);
    
    is($order_cb_called, 2);
}

sub tiny_timer_cb {
    my ($handle, $status) = @_;
    is($handle, $tiny_timer);
    $loop->close($tiny_timer, undef);
    $loop->close($huge_timer1, undef);
    $loop->close($huge_timer2, undef);
}

#TEST_IMPL(timer_huge_timeout)
{
    $loop->timer_init($tiny_timer);
    $loop->timer_init($huge_timer1);
    $loop->timer_init($huge_timer2);
    $loop->timer_start($tiny_timer, \&tiny_timer_cb, 1, 0);
    $loop->timer_start($huge_timer1, \&tiny_timer_cb, 99**99**99, 0);
    $loop->timer_start($huge_timer2, \&tiny_timer_cb, 2, 0); ##FIXME 2 should be -1
    $loop->run($Rum::Loop::RUN_DEFAULT);
}


my $ncalls = 0;
sub huge_repeat_cb {
    my ($handle, $status) = @_;
    
    if ($ncalls == 0){
        is($handle,$huge_timer1);
    } else {
        is($handle, $tiny_timer);
    }
    
    if (++$ncalls == 10) {
        $loop->close($tiny_timer);
        $loop->close($huge_timer1);
    }
}

#TEST_IMPL(timer_huge_repeat)
{
    $loop->timer_init($tiny_timer);
    $loop->timer_init($huge_timer1);
    $loop->timer_start($tiny_timer, \&huge_repeat_cb, 2, 2);
    $loop->timer_start($huge_timer1, \&huge_repeat_cb, 1, 9999); ##FIX 999 should be -1
    $loop->run($Rum::Loop::RUN_DEFAULT);
}


my $timer_run_once_timer_cb_called = 0;


sub timer_run_once_timer_cb {
    $timer_run_once_timer_cb_called++;
}

#TEST_IMPL(timer_run_once) 
{
    my $timer_handle = {};
    
    $loop->timer_init($timer_handle);
    $loop->timer_start($timer_handle, \&timer_run_once_timer_cb, 0, 0);
    $loop->run($Rum::Loop::RUN_ONCE);
    is($timer_run_once_timer_cb_called,1);
    
    $loop->timer_start($timer_handle, \&timer_run_once_timer_cb, 1, 0);
    $loop->run($Rum::Loop::RUN_ONCE);
    is($timer_run_once_timer_cb_called,2);
    
    $loop->close($timer_handle);
    ok(0 == $loop->run($Rum::Loop::RUN_ONCE));
}

done_testing();

1;

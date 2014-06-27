use lib './lib';
use Rum::Loop;
use Test::More;

my $prepare_handle = {};
my $check_handle = {};
my $timer_handle = {};

my $prepare_cb_called = 0;
my $check_cb_called = 0;
my $timer_cb_called = 0;
my $loop = Rum::Loop::default_loop();

sub prepare_cb {
    my ($handle, $status) = @_;
    ok(0 == $loop->prepare_stop($prepare_handle));
    ok(0 == $prepare_cb_called);
    ok(1 == $check_cb_called);
    is($timer_cb_called,0);
    $prepare_cb_called++;
}

sub timer_cb {
    my ($handle, $status) = @_;
    ok(0 == Rum::Loop::default_loop()->timer_stop($timer_handle));
    ok(1 == $prepare_cb_called);
    ok(1 == $check_cb_called);
    ok(0 == $timer_cb_called);
    $timer_cb_called++;
}

sub check_cb {
    my ($handle, $status) = @_;
    Rum::Loop::default_loop()->check_stop($check_handle);
    
    $loop->timer_stop($timer_handle);  # Runs before timer_cb.
    $loop->timer_start($timer_handle, \&timer_cb, 50, 0);
    
    $loop->prepare_start($prepare_handle, \&prepare_cb);
    ok(0 == $prepare_cb_called);
    ok(0 == $check_cb_called);
    ok(0 == $timer_cb_called);
    $check_cb_called++;
}

#TEST_IMPL(timer_from_check)
{
    Rum::Loop::prepare_init(Rum::Loop::default_loop(), $prepare_handle);
    
    Rum::Loop::check_init(Rum::Loop::default_loop(), $check_handle);
    Rum::Loop::default_loop()->check_start($check_handle, \&check_cb);
    
    Rum::Loop::timer_init(Rum::Loop::default_loop(), $timer_handle);
    Rum::Loop::default_loop()->timer_start($timer_handle, \&timer_cb, 50, 0);
    
    Rum::Loop::run(Rum::Loop::default_loop(), $Rum::Loop::RUN_DEFAULT);
    ok(1 == $prepare_cb_called);
    ok(1 == $check_cb_called);
    ok(1 == $timer_cb_called);
    
    Rum::Loop::default_loop()->close($prepare_handle);
    Rum::Loop::default_loop()->close($check_handle);
    Rum::Loop::default_loop()->close($timer_handle);
    
    ok( 0 == Rum::Loop::run(Rum::Loop::default_loop(), $Rum::Loop::RUN_ONCE) );
}

done_testing();

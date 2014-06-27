use lib './lib';
use Rum::Loop;
use Test::More;

my $idle_handle = {};
my $check_handle = {};
my $timer_handle = {};

my $idle_cb_called = 0;
my $check_cb_called = 0;
my $timer_cb_called = 0;
my $close_cb_called = 0;

my $loop = Rum::Loop->new();

sub close_cb {
    $close_cb_called++;
}


sub timer_cb {
    my ($handle, $status) = @_;
    is($handle, $timer_handle);
    ok($status == 0);

    $loop->close($idle_handle, \&close_cb);
    $loop->close($check_handle, \&close_cb);
    $loop->close($timer_handle, \&close_cb);

    $timer_cb_called++;
    printf("timer_cb %d\n", $timer_cb_called);
}

sub idle_cb {
    my ($handle, $status) = @_;
    is($handle, $idle_handle);
    ok($status == 0);
    
    $idle_cb_called++;
    printf("idle_cb %d\n", $idle_cb_called);
}

sub check_cb {
    my ($handle, $status) = @_;
    is($handle, $check_handle);
    ok($status == 0);
    $check_cb_called++;
    printf("check_cb %d\n", $check_cb_called);
}

#TEST_IMPL(idle_starvation)
{
    
    $loop->idle_init($idle_handle);
    $loop->idle_start($idle_handle, \&idle_cb);
    
    $loop->check_init($check_handle);
    $loop->check_start($check_handle, \&check_cb);
  
    $loop->timer_init($timer_handle);
    $loop->timer_start($timer_handle, \&timer_cb, 50, 0);
    
    $loop->run();
    
    ok($idle_cb_called > 0);
    is($timer_cb_called, 1);
    is($close_cb_called, 3);

}

done_testing();

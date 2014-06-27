use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Test::More;

my $timer_handle = {};
my $timer_called = 0;


sub timer_cb {
    my ($handle, $status) = @_;
    is($handle, $timer_handle);
    ok($status == 0);
    $timer_called = 1;
}

{
    my $loop = Rum::Loop->new();
    $loop->timer_init($timer_handle);
    $loop->timer_start($timer_handle, \&timer_cb, 100, 100);
    
    my $r = $loop->run(RUN_NOWAIT);
    ok($r != 0);
    is($timer_called, 0);
}

done_testing();

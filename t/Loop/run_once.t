use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Test::More;

my $NUM_TICKS = 64;

my $idle_handle = {};
my $idle_counter = 0;

my $loop = Rum::Loop::default_loop();

sub idle_cb {
    my ($handle, $status) = @_;
    is($handle, $idle_handle);
    ok($status == 0);
    
    if (++$idle_counter == $NUM_TICKS) {
        $loop->idle_stop($handle);
    }
}

{
    
    $loop->idle_init($idle_handle);
    $loop->idle_start($idle_handle, \&idle_cb);
    
    while ($loop->run($Rum::Loop::RUN_ONCE)){};
    is($idle_counter, $NUM_TICKS);
}

done_testing();

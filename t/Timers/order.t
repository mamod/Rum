use strict;
use warnings;
use Rum::Timers;
use Test::More;
use Time::HiRes 'time';
my $i;
my $N = 30;

my $last_i = 0;
my $last_ts = 0;
my $start = time();

my $f; $f = sub  {
    my ($self,$i) = @_;
    if ($i <= $N) {
        #check order
        is($i, $last_i + 1, 'order is broken: ' . $i . ' != ' . $last_i . ' + 1');
        $last_i = $i;
        #check that this iteration is fired at least 1ms later than the previous
        my $now = Rum::Timers::now();
        ok($now >= $last_ts + 1, 'current ts ' . $now . ' < prev ts ' . $last_ts . ' + 1');
        $last_ts = $now;
        #schedule next iteration
        setTimeout($f, 10, $i + 1);
    }
};
$f->({},1);

start_timers();
done_testing();

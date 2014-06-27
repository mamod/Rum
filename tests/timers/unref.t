use Rum;
use Test::More;
my $assert = Require('assert');

my $interval_fired = 0;
my $timeout_fired = 0;
my $unref_interval = 0;
my $unref_timer = 0;
my $interval;
my $check_unref;
my $checks = 0;

my $LONG_TIME = 10 * 1000;
my $SHORT_TIME = 100;

setInterval( sub {
    $interval_fired = 1;
}, $LONG_TIME)->unref();

setTimeout(sub {
    $timeout_fired = 1;
}, $LONG_TIME)->unref();

$interval = setInterval(sub {
    $unref_interval = 1;
    clearInterval($interval);
}, $SHORT_TIME)->unref();

setTimeout(sub {
    $unref_timer = 1;
}, $SHORT_TIME)->unref();

$check_unref = setInterval(sub {
    if ($checks > 5 || ($unref_interval && $unref_timer)){
        clearInterval($check_unref);
    }
    
    $checks += 1;
}, 100);

#Should not assert on args.Holder()->InternalFieldCount() > 0. See #4261.
#(function() {
#  var t = setInterval(function() {}, 1);
#  process.nextTick(t.unref.bind({}));
#  process.nextTick(t.unref.bind(t));
#})();

process->on('exit', sub {
    is($interval_fired, 0, 'Interval should not fire');
    is($timeout_fired, 0, 'Timeout should not fire');
    is($unref_timer, 1, 'An unrefd timeout should still fire');
    is($unref_interval, 1, 'An unrefd interval should still fire');
    done_testing(4);
});

1;


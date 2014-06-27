use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $events = Require('events');

my $e = $events->new();
my $times_hello_emited = 0;

$e->once('hello', sub {
    $times_hello_emited++;
});

$e->emit('hello', 'a', 'b');
$e->emit('hello', 'a', 'b');
$e->emit('hello', 'a', 'b');
$e->emit('hello', 'a', 'b');

my $remove = sub {
    fail('once->foo should not be emitted');
};

$e->once('foo', $remove);
$e->removeListener('foo', $remove);
$e->emit('foo');

process->on('exit', sub {
    is(1, $times_hello_emited);
});

my $times_recurse_emitted = 0;

$e->once('e', sub {
    $e->emit('e');
    $times_recurse_emitted++;
});

$e->once('e', sub {
    $times_recurse_emitted++;
});

$e->emit('e');

process->on('exit', sub {
    is(2, $times_recurse_emitted);
    done_testing(2);
});

1;

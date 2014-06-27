use Rum;
use Test::More;
use Data::Dumper;

my $common = Require('../common');
my $assert = Require('assert');
my $events = Require('events');

my $callbacks_called = [];

my $e = $events->new();

sub callback1 {
    push @{$callbacks_called},'callback1';
    $e->on('foo', \&callback2);
    $e->on('foo', \&callback3);
    $e->removeListener('foo', \&callback1);
}

sub callback2 {
    push @{$callbacks_called},'callback2';
    $e->removeListener('foo', \&callback2);
}

sub callback3 {
    push @{$callbacks_called}, 'callback3';
    $e->removeListener('foo', \&callback3);
}

$e->on('foo', \&callback1);
is(1, scalar @{$e->listeners('foo')});

$e->emit('foo');
is(2, scalar @{$e->listeners('foo')});
is_deeply(['callback1'], $callbacks_called);

$e->emit('foo');
is(0, scalar @{$e->listeners('foo')});
is_deeply(['callback1', 'callback2', 'callback3'], $callbacks_called);

$e->emit('foo');
is(0, scalar @{$e->listeners('foo')});
is_deeply(['callback1', 'callback2', 'callback3'], $callbacks_called);

$e->on('foo', \&callback1);
$e->on('foo', \&callback2);
is(2, scalar @{$e->listeners('foo')});
$e->removeAllListeners('foo');
is(0, scalar @{$e->listeners('foo')});

#Verify that removing callbacks while in emit allows emits to propagate to
#all listeners
$callbacks_called = [];

$e->on('foo', \&callback2);
$e->on('foo', \&callback3);
is(2, scalar @{$e->listeners('foo')});
$e->emit('foo');
is_deeply(['callback2', 'callback3'], $callbacks_called);
is(0, scalar @{$e->listeners('foo')});

done_testing(12);

1;

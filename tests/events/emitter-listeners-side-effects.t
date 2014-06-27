use Rum;
use Test::More;

sub _ok {
    
}

sub _fail {
    
}

my $common = Require('../common');
my $assert = Require('assert');
my $events = Require('events');
my $EventEmitter = Require('events');

my $e = $EventEmitter->new();
my $fl;  #foo listeners

$fl = $e->listeners('foo');

ok(ref $fl eq 'ARRAY');
ok(scalar @{$fl} == 0);
is_deeply($e->{_events}, {});

$e->on('foo', \&_fail);
$fl = $e->listeners('foo');

ok($e->{_events}->{foo} == \&_fail);
ok(ref $fl eq 'ARRAY');
ok(scalar @{$fl} == 1);
ok($fl->[0] == \&_fail);

$e->listeners('bar');
ok(!$e->{_events}->{'bar'});

$e->on('foo', \&_ok);
$fl = $e->listeners('foo');

ok(ref $e->{_events}->{foo} eq 'ARRAY');
ok(scalar @{$e->{_events}->{foo}} == 2);
ok($e->{_events}->{foo}->[0] == \&_fail);
ok($e->{_events}->{foo}->[1] == \&_ok);

ok(ref $fl eq 'ARRAY');
ok(scalar @{$fl} == 2);
ok($fl->[0] == \&_fail);
ok($fl->[1] == \&_ok);


done_testing(16);

1;

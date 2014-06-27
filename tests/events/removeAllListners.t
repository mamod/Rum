use Rum;
use Test::More;

my $assert = Require('assert');
my $events = Require('events');

sub expect {
    
    my $expected = $_[0];
    my $actual = [];
    process->on('exit', sub {
        my @sort1 = sort @{$actual};
        my @sort2 = sort @{$expected};
        is_deeply(\@sort1, \@sort2);
    });
    
    my $listener = sub {
        my ($this,$name) = @_;
        pass "Listner Called";
        push @{$actual}, $name;
    };
    
    return $listener;
}

sub listener {}

my $e1 = $events->new();
$e1->on('foo', \&listener);
$e1->on('bar', \&listener);
$e1->on('baz', \&listener);
$e1->on('baz', \&listener);

my $fooListeners = $e1->listeners('foo');
my $barListeners = $e1->listeners('bar');
my $bazListeners = $e1->listeners('baz');
$e1->on('removeListener', expect(['bar', 'baz', 'baz']));

$e1->removeAllListeners('bar');
$e1->removeAllListeners('baz');

is_deeply(\@{$e1->listeners('foo')},[\&listener]);
is_deeply(\@{$e1->listeners('bar')}, []);
is_deeply(\@{$e1->listeners('baz')}, []);

#after calling removeAllListeners,
#the old listeners array should stay unchanged
is_deeply($fooListeners, [\&listener]);
is_deeply($barListeners, [\&listener]);
is_deeply($bazListeners, [\&listener, \&listener]);

##after calling removeAllListeners,
##new listeners arrays are different from the old
isn't(\@{$e1->listeners('bar')}, $barListeners);
isn't(\@{$e1->listeners('baz')}, $bazListeners);

my $e2 = $events->new();
$e2->on('foo', \&listener);
$e2->on('bar', \&listener);

##expect LIFO order
$e2->on('removeListener', expect(['foo', 'bar', 'removeListener']));
$e2->on('removeListener', expect(['foo', 'bar']));
$e2->removeAllListeners();

is_deeply([], \@{$e2->listeners('foo')});
is_deeply([], \@{$e2->listeners('bar')});

process->on('exit',sub{
    done_testing(21);
});

1;

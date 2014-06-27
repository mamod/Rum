use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $e = TEST::Events->new();

my @events_new_listener_emited = ();
my @listeners_new_listener_emited = ();
my $times_hello_emited = 0;

$e->on('newListener', sub {
    my ($this, $event, $listener) = @_;
    #console.log('newListener: ' + event);
    push @events_new_listener_emited,$event;
    push @listeners_new_listener_emited,$listener;
});

sub hello {
    my ($this, $a, $b) = @_;
    $times_hello_emited += 1;
    is('a', $a);
    is('b', $b);
}

$e->on('hello', \&hello);

my $foo = sub{};
$e->once('foo', $foo);

$e->emit('hello', 'a', 'b');

is_deeply(['hello', 'foo'], \@events_new_listener_emited);
is_deeply([\&hello, $foo], \@listeners_new_listener_emited);
is(1, $times_hello_emited);

done_testing();

package TEST::Events; {
    use warnings;
    use strict;
    ##extends Events
    use base 'Rum::Events';
    sub new {bless {},__PACKAGE__}
}

use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $e = TEST::Events->new();

#emitter-listeners-side-effects
{
    
    my $e = TEST::Events->new();
    my $fl;  #foo listeners
    
    $fl = $e->listeners('foo');
    ok(ref $fl eq 'ARRAY');
    ok(scalar @{$fl} == 0);
    
    $e->on('foo', \&fail);
    $fl = $e->listeners('foo');
    ok($e->{_events}->{foo} == \&fail);
    ok(ref $fl eq 'ARRAY');
    ok(scalar @{$fl} == 1);
    ok($fl->[0] == \&fail);
    
    $e->listeners('bar');
    ok(!$e->{_events}->{bar} );
    
    $e->on('foo', \&ok);
    $fl = $e->listeners('foo');
    
    ok(ref $e->{_events}->{foo} eq 'ARRAY');
    ok(scalar @{$e->{_events}->{foo}} == 2);
    ok($e->{_events}->{foo}->[0] == \&fail);
    ok($e->{_events}->{foo}->[1] == \&ok);
    
    ok(ref $fl eq 'ARRAY');
    ok( scalar @{$fl} == 2);
    ok($fl->[0] == \&fail);
    ok($fl->[1] == \&ok);
    
}

#event-emitter-listeners
{
    sub listener {}
    sub listener2 {}
    my $e1 = TEST::Events->new();
    $e1->on('foo', \&listener);
    my $fooListeners = $e1->listeners('foo');
    is($e1->listeners('foo')->[0], \&listener);
    ok(scalar @{$e1->listeners('foo')} == 1);
    ok(!$e1->listeners('foo')->[1]);
    $e1->removeAllListeners('foo');
    ok(!$e1->listeners('foo')->[0]);
    ok(scalar @{$e1->listeners('foo')} == 0);
    is_deeply($fooListeners, [\&listener]);
    #
    my $e2 = TEST::Events->new();
    $e2->on('foo', \&listener);
    my $e2ListenersCopy = $e2->listeners('foo');
    is_deeply($e2ListenersCopy, [\&listener]);
    my $r2 = $e2->listeners('foo');
    is_deeply( $r2, [\&listener]);
    push @$e2ListenersCopy, \&listener2;
    my $r1 = $e2->listeners('foo');
    is_deeply($r1, [\&listener]);
    is_deeply($e2ListenersCopy, [\&listener, \&listener2]);
    #
    my $e3 = TEST::Events->new();
    $e3->on('foo', \&listener);
    my $e3ListenersCopy = $e3->listeners('foo');
    $e3->on('foo', \&listener2);
    my $r3 = $e3->listeners('foo');
    is_deeply($r3, [\&listener, \&listener2]);
    is_deeply($e3ListenersCopy, [\&listener]);
}




done_testing();

package TEST::Events; {
    use warnings;
    use strict;
    ##extends Events
    use base 'Rum::Events';
    sub new {bless {},__PACKAGE__}
}

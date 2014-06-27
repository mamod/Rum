use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $e = TEST::Events->new();

for (0 .. 9) {
    $e->on('default', sub{});
}

ok( !$e->{_events_warned}->{'default'} );

$e->on('default', sub{});
ok($e->{_events_warned}->{'default'});


##specific
$e->setMaxListeners(5);
for (0 .. 4) {
    $e->on('specific', sub{});
}

ok( !$e->{_events_warned}->{'specific'} );
$e->on('specific', sub{});
ok( $e->{_events_warned}->{'specific'} );

#only one
$e->setMaxListeners(1);
$e->on('only one', sub {});
ok(!$e->{_events_warned}->{'only one'});
$e->on('only one', sub {});
ok($e->{_events_warned}->{'only one'});

{
    #process-wide
    $Rum::Events::defaultMaxListeners = 42;
    my $e = TEST::Events->new();
    
    for (0 .. 41) {
        $e->on('fortytwo', sub{});
    }
    
    ok(!$e->{_events_warned}->{'fortytwo'});
    $e->on('fortytwo', sub{});
    ok( $e->{_events_warned}->{'fortytwo'} );
    delete $e->{_events_warned}->{'fortytwo'};
    
    $Rum::Events::defaultMaxListeners = 44;
    $e->on('fortytwo', sub{});
    ok(!$e->{_events_warned}->{'fortytwo'});
    $e->on('fortytwo', sub{});
    ok($e->{_events_warned}->{'fortytwo'});
    
    #but _maxListeners still has precedence over defaultMaxListeners
    $Rum::Events::defaultMaxListeners = 42;
    $e->setMaxListeners(1);
    $e->on('uno', sub{});
    ok(!$e->{_events_warned}->{'uno'});
    $e->on('uno', sub{});
    ok($e->{_events_warned}->{'uno'});
    
    #chainable
    is($e, $e->setMaxListeners(1));
    
}

#unlimited
$e->setMaxListeners(0);
for (0 .. 999) {
    $e->on('unlimited', sub{});
}
ok(!$e->{_events_warned}->{'unlimited'});


done_testing();

package TEST::Events; {
    use warnings;
    use strict;
    ##extends Events
    use base 'Rum::Events';
    sub new {bless {},__PACKAGE__}
}

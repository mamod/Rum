use strict;
use warnings;
use Test::More;
use Data::Dumper;

my $Test;
BEGIN {
    eval {
        require Test::Exception;
        Test::Exception->import();
        $Test = 1;
    };
}

if (!$Test){
    plan skip_all => "Test::Exception REQUIRED TO RUN THIS TEST";
} else {
    plan tests => 14;
}


use Rum::Events;
my $event = TEST::Events->new();

throws_ok { $event->addListener() } qr/listener must be a function/, 'must die with no function listner';

##adding one Listener
$event->addListener('Hi',sub {});

##we should have an events key
ok($event->{_events});
##and it must be a hash ref
ok(ref $event->{_events} eq 'HASH');

##event listener is a code ref
ok(ref $event->{_events}->{Hi} eq 'CODE');

##adding another Listener with the same event name
$event->addListener('Hi', sub {});

##nmow event listener becomes an array ref
ok(ref $event->{_events}->{Hi} eq 'ARRAY');

##we now have 2
is(scalar @ { $event->{_events}->{Hi} }, 2);

my $sameSub = sub {};

##adding 2 more
$event->on('Hi', $sameSub);
$event->on('Hi', $sameSub);

throws_ok { $event->removeListener() } qr/listener must be a function/;
throws_ok { $event->removeListener('Hi') } qr/listener must be a function/;
throws_ok { $event->removeListener('Hi',{}) } qr/listener must be a function/;

$event->removeListener('Hi',sub{});

###nothing really has been removed
is(scalar @ { $event->{_events}->{Hi} }, 4);

###remove again
$event->removeListener('Hi',$sameSub);

##only one has been removed
is(scalar @ { $event->{_events}->{Hi} }, 3);

################################################emit
{
    my $ev = TEST::Events->new();
    my $i = 0;
    $ev->on('test1',sub {
        ++$i;
    });
    
    $ev->on('test2', sub {
        ++$i;
        shift->emit('test1');
    });
    
    $ev->emit('test2');
    is($i,2);
    
    throws_ok { $ev->emit('error') } qr/Uncaught, unspecified "error" event./;
    
    $ev->on('test2', sub {
        ++$i;
        shift->emit('test1');
    });
    
    $ev->emit('test2');
    is($i,6);
}

done_testing(14);

package TEST::Events; {
    use warnings;
    use strict;
    ##extends Events
    use base 'Rum::Events';
    sub new {bless {},__PACKAGE__}
}
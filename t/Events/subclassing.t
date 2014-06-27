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
}

my $called = 0;
my $myee = TEST::MyEE->new( sub {
  $called = 1;
});

throws_ok { TEST::ErrorEE->new() } qr/blerg/;

ok($called);
ok(ref $myee->{_events} eq 'HASH');

done_testing();

package TEST::MyEE; {
    use warnings;
    use strict;
    ##extends Events
    use base 'Rum::Events';
    sub new {
        my ($class,$cb) = @_;
        my $this = bless {}, __PACKAGE__;
        $this->once(1, $cb);
        $this->emit(1);
        $this->removeAllListeners(1);
    }
}

package TEST::ErrorEE; {
    use warnings;
    use strict;
    use Rum::Error;
    use base 'Rum::Events';
    sub new {
        bless({},shift)->emit('error', Rum::Error->new('blerg'));
    }
}

1

use strict;
use warnings;
use Rum::Utils;
use Test::More;

my $utils = Rum::Utils->new();

###numbers test
ok($utils->isNumber(1));
ok($utils->isNumber(-0));
ok($utils->isNumber(-0.90999999));
ok($utils->isNumber(6.90999999));
ok(!$utils->isNumber('1'));
ok(!$utils->isNumber('a'));
ok(!$utils->isNumber('1a2s'));
ok(!$utils->isNumber({}));
ok(!$utils->isNumber([]));
ok($utils->isNumber(2*9));
ok($utils->isNumber(-2*9));
ok($utils->isNumber(0xFF));


ok($utils->isString('1'));
ok($utils->isString( 'errt' . 'www' ));
ok(!$utils->isString( 1 ));
ok(!$utils->isString( {} ));
ok(!$utils->isString( [] ));

ok( $utils->likeNumber('1') );
ok( $utils->likeNumber(0) );

ok($utils->isFunction(sub{}));
sub noob{}
ok($utils->isFunction(\&noob));
ok(!$utils->isFunction('a'));
ok(!$utils->isFunction(8));

###number casting
{
    my $num = '99';
    ok (!$utils->isNumber($num));
    ok ($utils->isString($num));
    ok ($utils->likeNumber($num));
    is($num,99);
    $num +=1;
    ok ($utils->isNumber($num));
    ok (!$utils->isString($num));
    ok ($utils->likeNumber($num));
    is($num,100);
}

is ($utils->typeof(0), 'number');
is ($utils->typeof('0'), 'string');
is ($utils->typeof({}), 'hash');
is ($utils->typeof([]), 'array');
is ($utils->typeof('a'), 'string');
is ($utils->typeof(bless {},'TEST'), 'object');
is ($utils->typeof(), 'undefined');

my $inf = 9**9**9;
my $neginf = -9**9**9;
my $nan = -sin(9**9**9);

ok( $utils->isNaN($nan));
ok( !$utils->isNaN(-1.9) );

done_testing();

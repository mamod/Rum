use strict;
use warnings;
use Test::More;
use Rum::Buffer;
use utf8;
my $Buffer = 'Rum::Buffer';

#Binary encoding should write only one byte per character.
my $b = $Buffer->new([0xde, 0xad, 0xbe, 0xef]);
my $s = chr(0xff);
$b->write($s, 0, 'binary');
#diag($b);

is(0xff, $b->get(0));
is(0xad, $b->get(1));
is(0xbe, $b->get(2));
is(0xef, $b->get(3));
$s = chr(0xaaee);
$b->write($s, 0, 'binary');
is(0xee, $b->get(0));
is(0xad, $b->get(1));
is(0xbe, $b->get(2));
is(0xef, $b->get(3));


done_testing(8);

use strict;
use warnings;
use Test::More 'tests' => 5;
use Rum::Buffer;

my $Buffer = 'Rum::Buffer';

my $zero = [];
my $one  = [ $Buffer->new('asdf') ];
my $long = [];
for (0 .. 9) { push @{$long}, $Buffer->new('asdf') }

my $flatZero = $Buffer->concat($zero);
my $flatOne = $Buffer->concat($one);
my $flatLong = $Buffer->concat($long);
my $flatLongLen = $Buffer->concat($long, 40);

ok($flatZero->length == 0);
ok($flatOne->toString() eq 'asdf');
ok($flatOne eq $one->[0]);
is( $flatLong->toString(), 'asdf' x 10 );
is($flatLongLen->toString(),  'asdf' x 10 );

done_testing();

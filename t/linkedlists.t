use strict;
use warnings;
use Rum::LinkedLists;
use Test::More;

my $L = Rum::LinkedLists->new();

my $list = { name => 'list' };
my $A = { name => 'A' };
my $B = { name => 'B' };
my $C = { name => 'C' };
my $D = { name => 'D' };


$L->init($list);
$L->init($A);
$L->init($B);
$L->init($C);
$L->init($D);

ok($L->isEmpty($list));
is(undef, $L->peek($list));

$L->append($list, $A);
#list -> A
is($A, $L->peek($list));

$L->append($list, $B);
#list -> A -> B
is($A, $L->peek($list));

$L->append($list, $C);
#list -> A -> B -> C
is($A, $L->peek($list));

$L->append($list, $D);
#list -> A -> B -> C -> D
is($A, $L->peek($list));

my $x = $L->shift($list);
is($A, $x);
#list -> B -> C -> D
is($B, $L->peek($list));

$x = $L->shift($list);
is($B, $x);
#list -> C -> D
is($C, $L->peek($list));

#B is already removed, so removing it again shouldn't hurt.
$L->remove($B);
#list -> C -> D
is($C, $L->peek($list));

#Put B back on the list
$L->append($list, $B);
#list -> C -> D -> B
is($C, $L->peek($list));

$L->remove($C);
#list -> D -> B
is($D, $L->peek($list));

$L->remove($B);
#list -> D
is($D, $L->peek($list));

$L->remove($D);
#list
is(undef, $L->peek($list));


ok($L->isEmpty($list));


$L->append($list, $D);
# list -> D
is($D, $L->peek($list));

$L->append($list, $C);
$L->append($list, $B);
$L->append($list, $A);
#list -> D -> C -> B -> A

#Append should REMOVE C from the list and append it to the end.
$L->append($list, $C);

#list -> D -> B -> A -> C
is($D, $L->shift($list));
#list -> B -> A -> C
is($B, $L->peek($list));
is($B, $L->shift($list));
#list -> A -> C
is($A, $L->peek($list));
is($A, $L->shift($list));
#list -> C
is($C, $L->peek($list));
is($C, $L->shift($list));
#list
ok($L->isEmpty($list));

done_testing(25);


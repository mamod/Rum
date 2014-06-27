use Rum;
use Test::More;
my $common = Require('../common');
my $assert = Require('assert');
my $path = Require('path');
my $fs = Require('fs');



my $fn = $path->join($common->{fixturesDir}, 'elipses.txt');
my $s = $fs->readFileSync($fn,'utf-8');
is(length $s, 10000);
is(bytes::length $s, 30000);

my @chars = split //, $s;

{
    use utf8;
    is($chars[0], "…");
    no utf8;
}

for (0 .. 1000){
    is($chars[$_],"\x{2026}");
}

done_testing();

1;

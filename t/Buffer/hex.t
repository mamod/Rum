use strict;
use warnings;
use lib './lib';
use Test::More;
use Rum::Buffer;
my $Buffer = 'Rum::Buffer';

#test hex toString
my $hexb = $Buffer->new(256);
for (my $i = 0; $i < 256; $i++) {
    $hexb->set($i,$i);
}

my $hexStr = $hexb->toString('hex');

is($hexStr,
    '000102030405060708090a0b0c0d0e0f' .
    '101112131415161718191a1b1c1d1e1f' .
    '202122232425262728292a2b2c2d2e2f' .
    '303132333435363738393a3b3c3d3e3f' .
    '404142434445464748494a4b4c4d4e4f' .
    '505152535455565758595a5b5c5d5e5f' .
    '606162636465666768696a6b6c6d6e6f' .
    '707172737475767778797a7b7c7d7e7f' .
    '808182838485868788898a8b8c8d8e8f' .
    '909192939495969798999a9b9c9d9e9f' .
    'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf' .
    'b0b1b2b3b4b5b6b7b8b9babbbcbdbebf' .
    'c0c1c2c3c4c5c6c7c8c9cacbcccdcecf' .
    'd0d1d2d3d4d5d6d7d8d9dadbdcdddedf' .
    'e0e1e2e3e4e5e6e7e8e9eaebecedeeef' .
    'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff');

my $hexb2 = $Buffer->new($hexStr, 'hex');

#diag($hexb);

for (my $i = 0; $i < 256; $i++) {
    is($hexb2->get($i), $hexb->get($i));
}


#test an invalid slice end.
my $b = $Buffer->new([1, 2, 3, 4, 5]);
my $b2 = $b->toString('hex', 1, 10000);
my $b3 = $b->toString('hex', 1, 5);
my $b4 = $b->toString('hex', 1);
is($b2, $b3);
is($b2, $b4);
#
#test.plan(259);

done_testing(259);

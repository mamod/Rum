use strict;
use warnings;
use lib './lib';
use Rum::Buffer;
my $Buffer = 'Rum::Buffer';
use Data::Dumper;
use Test::More;

{
    my $b = $Buffer->new('محمود ', 'utf8');
    is($b,'<Buffer d9 85 d8 ad d9 85 d9 88 d8 af 20>');
    is($b->length,11);
    is(length $b->toString(), 6);
    is(length $b->toString('binary'), 11);
    is(length $b->toString('hex'),22);
    is(length $b->toString('base64'), 16);
    is(length $b->toString('ucs2'), 5);
    is(length $b->toString('ascii'), 11);
}

{
    my $b = $Buffer->new('محمود ', 'ascii');
    is($b,'<Buffer 45 2d 45 48 2f 20>');
    is($b->length,6);
    is(length $b->toString(), 6);
    is(length $b->toString('binary'), 6);
    is(length $b->toString('hex'),12);
    is(length $b->toString('base64'), 8);
    is(length $b->toString('ucs2'), 3);
    is(length $b->toString('ascii'), 6);
}

{
    my $b = $Buffer->new('محمود ', 'ucs2');
    is($b,'<Buffer 45 06 2d 06 45 06 48 06 2f 06 20 00>');
    is($b->length,12);
    is(length $b->toString(), 12);
    is(length $b->toString('binary'), 12);
    is(length $b->toString('hex'),24);
    is(length $b->toString('base64'), 16);
    is(length $b->toString('ucs2'), 6);
    is(length $b->toString('ascii'), 12);
}

{
    my $b = $Buffer->new('محمود ', 'binary');
    is($b,'<Buffer 45 2d 45 48 2f 20>');
    is($b->length,6);
    is(length $b->toString(), 6);
    is(length $b->toString('binary'), 6);
    is(length $b->toString('hex'),12);
    is(length $b->toString('base64'), 8);
    is(length $b->toString('ucs2'), 3);
    is(length $b->toString('ascii'), 6);
}

##todo
#{
#    my $b = $Buffer->new('محمود ', 'base64');
#    is($b,'<Buffer 13 e1 07>');
#    is($b->length,3);
#    is(length $b->toString(), 3);
#    is(length $b->toString('binary'), 3);
#    is(length $b->toString('hex'),6);
#    is(length $b->toString('base64'), 4);
#    is(length $b->toString('ucs2'), 1);
#    is(length $b->toString('ascii'), 3);
#}

done_testing();

1;

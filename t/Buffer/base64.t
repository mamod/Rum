use strict;
use warnings;
use Test::More;
use Rum::Buffer;
use Rum;
my $Buffer = 'Rum::Buffer';

#big example
my $quote = 'Man is distinguished, not only by his reason, but by this ' .
            'singular passion from other animals, which is a lust ' .
            'of the mind, that by a perseverance of delight in the continued ' .
            'and indefatigable generation of knowledge, exceeds the short ' .
            'vehemence of any carnal pleasure.';


my @expected = ('TWFuIGlzIGRpc3Rpbmd1aXNoZWQsIG5vdCBvbmx5IGJ5IGhpcyByZWFzb24s',
               'IGJ1dCBieSB0aGlzIHNpbmd1bGFyIHBhc3Npb24gZnJvbSBvdGhlciBhbmltY',
               'WxzLCB3aGljaCBpcyBhIGx1c3Qgb2YgdGhlIG1pbmQsIHRoYXQgYnkgYSBwZX',
               'JzZXZlcmFuY2Ugb2YgZGVsaWdodCBpbiB0aGUgY29udGludWVkIGFuZCBpbmR',
               'lZmF0aWdhYmxlIGdlbmVyYXRpb24gb2Yga25vd2xlZGdlLCBleGNlZWRzIHRo',
               'ZSBzaG9ydCB2ZWhlbWVuY2Ugb2YgYW55IGNhcm5hbCBwbGVhc3VyZS4=');

my $expected = join '', @expected;

is($expected, $Buffer->new($quote)->toString('base64'));

my $b = $Buffer->new(1024);
my $bytesWritten = $b->write($expected, 0, 'base64');

is(length $quote, $bytesWritten);
is($quote, $b->toString('ascii', 0, length $quote));
#=======================================================================================
# do we ignore new lines
#=======================================================================================
{
    my $expectedWhite = join "\n", @expected;    
    $b = $Buffer->new(1024);
    $bytesWritten = $b->write($expectedWhite, 0, 'base64');
    is(length $quote, $bytesWritten);
    is($quote, $b->toString('ascii', 0, length $quote));
    
    ## check that the base64 decoder on the constructor works
    ## even in the presence of whitespace.
    
    $b = $Buffer->new($expectedWhite, 'base64');
    is(length $quote, $b->length);
    is($quote, $b->toString('ascii', 0, length $quote));
    
}

#=======================================================================================
# do we ignore illegal characters
#=======================================================================================
## check that the base64 decoder ignores illegal chars
{
    my $i = 0;
    my $expectedIllegal = '';
    map {
        $expectedIllegal .= $expected[$i]  . $_;
        $i++;
    }(" \x80"," \xff"," \xf0"," \x98","\x03");
    
    $expectedIllegal .= $expected[$i];
    
    my $b = $Buffer->new($expectedIllegal, 'base64');
    is(length $quote, $b->length);
    is($quote, $b->toString('ascii', 0, length $quote));
}

is($Buffer->new('', 'base64')->toString(), '');
is($Buffer->new('K', 'base64')->toString(), '');

#=======================================================================================
## multiple-of-4 with padding
#=======================================================================================
{
    is($Buffer->new('Kg==', 'base64')->toString(), '*');
    is($Buffer->new('Kio=', 'base64')->toString(), '**');
    is($Buffer->new('Kioq', 'base64')->toString(), '***');
    is($Buffer->new('KioqKg==', 'base64')->toString(), '****');
    is($Buffer->new('KioqKio=', 'base64')->toString(), '*****');
    is($Buffer->new('KioqKioq', 'base64')->toString(), '******');
    is($Buffer->new('KioqKioqKg==', 'base64')->toString(), '*******');
    is($Buffer->new('KioqKioqKio=', 'base64')->toString(), '********');
    is($Buffer->new('KioqKioqKioq', 'base64')->toString(), '*********');
    is($Buffer->new('KioqKioqKioqKg==', 'base64')->toString(),
                 '**********');
    is($Buffer->new('KioqKioqKioqKio=', 'base64')->toString(),
                 '***********');
    is($Buffer->new('KioqKioqKioqKioq', 'base64')->toString(),
                 '************');
    is($Buffer->new('KioqKioqKioqKioqKg==', 'base64')->toString(),
                 '*************');
    is($Buffer->new('KioqKioqKioqKioqKio=', 'base64')->toString(),
                 '**************');
    is($Buffer->new('KioqKioqKioqKioqKioq', 'base64')->toString(),
                 '***************');
    is($Buffer->new('KioqKioqKioqKioqKioqKg==', 'base64')->toString(),
                 '****************');
    is($Buffer->new('KioqKioqKioqKioqKioqKio=', 'base64')->toString(),
                 '*****************');
    is($Buffer->new('KioqKioqKioqKioqKioqKioq', 'base64')->toString(),
                 '******************');
    is($Buffer->new('KioqKioqKioqKioqKioqKioqKg==', 'base64')->toString(),
                 '*******************');
    is($Buffer->new('KioqKioqKioqKioqKioqKioqKio=', 'base64')->toString(),
                 '********************');
}

#=======================================================================================
## no padding, not a multiple of 4
#=======================================================================================
{
    is($Buffer->new('Kg', 'base64')->toString(), '*');
    is($Buffer->new('Kio', 'base64')->toString(), '**');
    is($Buffer->new('KioqKg', 'base64')->toString(), '****');
    is($Buffer->new('KioqKio', 'base64')->toString(), '*****');
    is($Buffer->new('KioqKioqKg', 'base64')->toString(), '*******');
    is($Buffer->new('KioqKioqKio', 'base64')->toString(), '********');
    is($Buffer->new('KioqKioqKioqKg', 'base64')->toString(), '**********');
    is($Buffer->new('KioqKioqKioqKio', 'base64')->toString(), '***********');
    is($Buffer->new('KioqKioqKioqKioqKg', 'base64')->toString(),
                 '*************');
    is($Buffer->new('KioqKioqKioqKioqKio', 'base64')->toString(),
                 '**************');
    is($Buffer->new('KioqKioqKioqKioqKioqKg', 'base64')->toString(),
                 '****************');
    is($Buffer->new('KioqKioqKioqKioqKioqKio', 'base64')->toString(),
                 '*****************');
    is($Buffer->new('KioqKioqKioqKioqKioqKioqKg', 'base64')->toString(),
                 '*******************');
    is($Buffer->new('KioqKioqKioqKioqKioqKioqKio', 'base64')->toString(),
                 '********************');
}

#=======================================================================================
# handle padding graciously, multiple-of-4 or not
#=======================================================================================
is($Buffer->new('72INjkR5fchcxk9+VgdGPFJDxUBFR5/rMFsghgxADiw==',
                        'base64')->length, 32);
is($Buffer->new('72INjkR5fchcxk9+VgdGPFJDxUBFR5/rMFsghgxADiw=',
                        'base64')->length, 32);
is($Buffer->new('72INjkR5fchcxk9+VgdGPFJDxUBFR5/rMFsghgxADiw',
                        'base64')->length, 32);
is($Buffer->new('w69jACy6BgZmaFvv96HG6MYksWytuZu3T1FvGnulPg==',
                        'base64')->length, 31);
is($Buffer->new('w69jACy6BgZmaFvv96HG6MYksWytuZu3T1FvGnulPg=',
                        'base64')->length, 31);
is($Buffer->new('w69jACy6BgZmaFvv96HG6MYksWytuZu3T1FvGnulPg',
                        'base64')->length, 31);

#=======================================================================================
## This string encodes single '.' character in UTF-16
#=======================================================================================
{
    my $dot = $Buffer->new('//4uAA==', 'base64');    
    is($dot->get(0), 0xff);
    is($dot->get(1), 0xfe);
    is($dot->get(2), 0x2e);
    is($dot->get(3), 0x00);
    is($dot->toString('base64'), '//4uAA==');
}

#=======================================================================================
## Creating buffers larger than pool size.
#=======================================================================================
{
    my $l = 8196;
    my $s = '';
    for (my $i = 0; $i < $l; $i++) {
        $s .= 'h';
    }
    
    my $b = $Buffer->new($s);
    
    for (my $i = 0; $i < $l; $i++) {
        ok(ord 'h' == $b->($i));
    }
    
    my $sb = $b->toString();
    is(length $sb, length $s);
    is($sb,$s);
}

#test.plan(56);


done_testing();

use strict;
use warnings;
use lib './lib';
use Test::More;
use Rum::Buffer;
use utf8;

my $Buffer = 'Rum::Buffer';

my $writeTest = $Buffer->new('abcdes');
$writeTest->write('p', 'ascii');
$writeTest->write('o', '1', 'ascii');
$writeTest->write('d', 2, 'ascii');
$writeTest->write('e', '3', 'ascii');
$writeTest->write('j', 4, 'ascii');

is($writeTest->toString(), 'podejs');

#Make sure that strings are not coerced to numbers.
is($Buffer->new('99')->length, 2);
is($Buffer->new('13.37')->length, 5);

#Ensure that the length argument is respected.
foreach my $enc (qw(ascii utf8 hex base64 binary)) {
    is($Buffer->new(1)->write('aaaaaa', 0, 1, $enc), 1);
}

{
    #Regression test, guard against buffer overrun in the base64 decoder.
    my $a = $Buffer->new(3);
    my $b = $Buffer->new('xxx');
    $a->write('aaaaaaaa', 'base64');
    is($b->toString(), 'xxx');
}

#Bug regression test
my $testValue = '\x{f6}\x{65e5}\x{672c}\x{8a9e}'; # ö日本語
my $buffer = $Buffer->new(32);
my $size = $buffer->write($testValue, 0, 'utf8');
my $slice = $buffer->toString('utf8', 0, $size);
is($slice, $testValue);

{
    my $e = $Buffer->new('über');
    my $e2 = $Buffer->new([195, 188, 98, 101, 114]);
    is_deeply($e, $e2);
    is($e->toString(),$e2->toString());
}


{
    my $d = $Buffer->new([23, 42, 255]);
    is($d->length, 3);
    is($d->get(0), 23);
    is($d->get(1), 42);
    is($d->get(2), 255);
    is_deeply($d, $Buffer->new($d));
}


#=======================================================================================
#copy example test
#=======================================================================================
{
    
    my $buf1 = $Buffer->new(26);
    my $buf2 = $Buffer->new(26);
    for (my $i = 0 ; $i < 26 ; $i++) {
        $buf1->set($i,$i + 97); # 97 is ASCII a
        $buf2->set($i, 33); # ASCII !
    }
    
    $buf1->copy($buf2, 8, 16, 20);
    is($buf2->toString('ascii', 0, 25),'!!!!!!!!qrst!!!!!!!!!!!!!');
}

#=======================================================================================
#Single slice
#=======================================================================================
{

    my $b = $Buffer->new('abcde');
    is('bcde', $b->slice(1)->toString());
    #slice(0,0)->length === 0
    is(0, $Buffer->new('hello')->slice(0, 0)->length);
}

my $written;
#=======================================================================================
# bytes written
#=======================================================================================
{
    
    #fixme
    my $buf = $Buffer->new("\0");
    is($buf->length, 1);
    $buf = $Buffer->new("\0\0");
    is($buf->length, 2);
    
    #unlike node buffer, buffers here if character has 3 bytes 2 will be added
    $buf = $Buffer->new(2);
    $written = $buf->write(''); # 0byte
    is($written, 0);
    
    $written = $buf->write("\0"); ## 1byte (v8 adds null terminator)
    is($written, 1);
    
    $written = $buf->write('a\0'); ## 1byte * 2
    is($written, 2);
    
    $written = $buf->write('あ'); # 3bytes
    is($written, 2);
    
    $written = $buf->write("\0あ"); #1byte + 3bytes
    is($written, 2);
    
    $written = $buf->write("\0\0あ"); # 1byte * 2 + 3bytes
    is($written, 2);
    
    $buf = $Buffer->new(10);
    $written = $buf->write('あいう'); # 3bytes * 3 (v8 adds null terminator)
    is($written, 9);
    $written = $buf->write("あいう\0"); # 3bytes * 3 + 1byte
    is($written, 10);
    
}


#=======================================================================================
#Test write() with maxLength
#=======================================================================================
{
    
    my $buf = $Buffer->new(4);
    $buf->fill(0xFF);
    $written = $buf->write('abcd', 1, 2, 'utf8');
    #console.log(buf);
    is($written, 2);
    is($buf->get(0), 0xFF);
    is($buf->get(1), 0x61);
    is($buf->get(2), 0x62);
    is($buf->get(3), 0xFF);
    
    $buf->fill(0xFF);
    $written = $buf->write('abcdef', 1, 2, 'hex');
    is($written, 2);
    is($buf->get(0), 0xFF);
    is($buf->get(1), 0xAB);
    is($buf->get(2), 0xCD);
    is($buf->get(3), 0xFF);
    
}

{
    ##ucs
    my $buf = $Buffer->new(4);
    foreach my $encoding ('ucs2', 'ucs-2', 'utf16le', 'utf-16le') {
        $buf->fill(0xFF);
        $written = $buf->write('abcd', 0, 2, $encoding);
        is($written, 2);
        is($buf->get(0), 0x61);
        is($buf->get(1), 0x00);
        is($buf->get(2), 0xFF);
        is($buf->get(3), 0xFF);
    }
}

#=======================================================================================
# test for buffer overrun
#=======================================================================================
{
    my $buf = $Buffer->new([0, 0, 0, 0, 0]); # length: 5
    my $sub = $buf->slice(0, 4);         # length: 4
    $written = $sub->write('12345', 'binary');
    is($written, 4);
    is($buf->get(4), 0);
}


{
    my $buf = $Buffer->new('0123456789');
    is($buf->slice(-10, 10)->toString(), '0123456789');
    is($buf->slice(-20, 10)->toString(), '0123456789');
    is($buf->slice(-20, -10)->toString(), '');
    is($buf->slice(0, -1)->toString(), '012345678');
    is($buf->slice(2, -2)->toString(), '234567');
    is($buf->slice(0, 65536)->toString(), '0123456789');
    is($buf->slice(65536, 0)->toString(), '');
    my $s = $buf->toString();
    for (my $i = 0; $i < $buf->length; ++$i) {
        is($buf->slice(-$i)->toString(), substr $s,-$i );
        is($buf->slice(0, -$i)->toString(), substr $s,0, -$i);
    }
}


done_testing();


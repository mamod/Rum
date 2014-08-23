use strict;
use warnings;
use Test::More;
use lib './lib';
use Rum::Buffer;
my $Buffer = 'Rum::Buffer';

my $segments = ['TWFkbmVzcz8h', 'IFRoaXM=', 'IGlz', 'IG5vZGUuanMh'];
my $b = $Buffer->new(64);
my $pos = 0;

for (my $i = 0; $i < scalar @{$segments}; ++$i) {
    $pos += $b->write($segments->[$i], $pos, 'base64');
}

is($b->toString('binary', 0, $pos), 'Madness?! This is node.js!');

sub buildBuffer {
    my ($data) = @_;
    if (ref $data eq 'ARRAY') {
        my $buffer = $Buffer->new(scalar @{$data});
        
        my $k = 0;
        foreach my $v (@$data){
            $buffer->set($k,$v);
            $k++;
        }
        
        return $buffer;
    }
  return undef;
}

my $x = buildBuffer([0x81, 0xa3, 0x66, 0x6f, 0x6f, 0xa3, 0x62, 0x61, 0x72]);

diag($x->inspect());
is('<Buffer 81 a3 66 6f 6f a3 62 61 72>', $x->inspect());

my $z = $x->slice(4);
is(5, $z->length);
is(0x6f, $z->[0]);
is(0xa3, $z->[1]);
is(0x62, $z->[2]);
is(0x61, $z->[3]);
is(0x72, $z->[4]);


$z = $x->slice(0);
is($z->length, $x->length);

$z = $x->slice(0, 4);
is(4, $z->length);
is(0x81, $z->[0]);
is(0xa3, $z->[1]);

$z = $x->slice(0, 9);
is(9, $z->length);

$z = $x->slice(1, 4);
is(3, $z->length);
is(0xa3, $z->[0]);

$z = $x->slice(2, 4);
is(2, $z->length);
is(0x66, $z->[0]);
is(0x6f, $z->[1]);

is(0, $Buffer->new('hello')->slice(0, 0)->length);


{
    
    my $b = $Buffer->new(50);
    $b->fill('h');
    for (my $i = 0; $i < $b->length; $i++) {
        is(ord 'h', $b->[$i]);
    }

    $b->fill(0);
    for (my $i = 0; $i < $b->length; $i++) {
        is(0, $b->[$i]);
    }

    $b->fill(1, 16, 32);
    for (my $i = 0; $i < 16; $i++) { is(0, $b->[$i]) }
    for (my $i = 16; $i < 32; $i++) { is(1, $b->[$i]) };
    for (my $i = 32; $i < $b->length; $i++) { is(0, $b->[$i]) };

    my $buf = $Buffer->new(10);
    $buf->fill('abc');
    is($buf->toString(), 'abcabcabca');
    $buf->fill('է');
    is($buf->toString(), 'էէէէէ');

    
    foreach my $encoding ('ucs2', 'ucs-2', 'utf16le', 'utf-16le'){
        my $b = $Buffer->new(10);
        $b->write('あいうえお', $encoding);
        is($b->toString($encoding), 'あいうえお');
    }
    
}

##sequential casting
{
    
    my $inspect = '<Buffer 42 44 46 48 4a>';

    my $buf = $Buffer->new('あいうえお', 'binary');
    is($buf->toString(), 'BDFHJ');
    is($buf, $inspect);
    $buf->write('あいうえお', 'ascii');
    is($buf->toString(), 'BDFHJ');
    is($buf, $inspect);
    
    my $b = $Buffer->new('مم', 'utf8');
    is($b,'<Buffer d9 85 d9 85>');
    $b->write('あいうえお', 'ascii');
    is($b,'<Buffer 42 44 46 48>');
    is($b->toString('hex'),42444648);
    
    $b->write('あいうえお', 0,50, 'ucs2');
    is ($b,'<Buffer 42 30 44 30>');
    
    is($b->length(), 4);
}

{
    my $inspect = '<Buffer 42 44 46 48 4a>';
    my $buf = $Buffer->new('あいうえお', 'binary');
    is($buf->toString(), 'BDFHJ');
    is($buf, $inspect);
    $buf->write('あいうえお', 'ascii');
    is($buf->toString(), 'BDFHJ');
    is($buf, $inspect);
    
    my $b = $Buffer->new('مم', 'utf8');
    is($b,'<Buffer d9 85 d9 85>');
    $b->write('あいうえお', 'ascii');
    is($b,'<Buffer 42 44 46 48>');
    is($b->toString('hex'),42444648);
    
    $b->write('あいうえお', 0,50, 'ucs2');
    is ($b,'<Buffer 42 30 44 30>');
    
    is($b->length(), 4);
}

done_testing();

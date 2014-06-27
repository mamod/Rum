use strict;
use warnings;
use Test::More;
use Rum::Buffer;

my $Buffer = 'Rum::Buffer';
my $jsontest = eval "use JSON; 1;";
if (!$jsontest){
	plan skip_all => "JSON REQUIRED TO RUN THIS TEST";
} else {
	plan tests => 80;
}

{
    #ASCII conversion in node.js simply masks off the high bits,
    #it doesn't do transliteration.
    is($Buffer->new('hérité','utf8')->toString('ascii'), 'hC)ritC)');
}


#71 characters, 78 bytes. The ’ character is a triple-byte sequence.
my $input =  'C’est, graphiquement, la réunion d’un accent aigu ' .
             'et d’un accent grave.';

my $expected = 'Cb\u0000\u0019est, graphiquement, la rC)union ' .
               'db\u0000\u0019un accent aigu et db\u0000\u0019un ' .
               'accent grave.';

my $json = JSON->new->ascii(1)->decode('{"str" : "'. $expected .'"}');
$expected = $json->{str};

my $buf = $Buffer->new($input);
my @expected = split //, $expected;
my $length = scalar @expected;

my $i = 0;
foreach my $ex (@expected){
    my $sliced = join ('', @expected[$i .. $length-1]);
    is($buf->slice($i)->toString('ascii'),  $sliced);
    $i++;
}

is($buf->length, $length);
done_testing();

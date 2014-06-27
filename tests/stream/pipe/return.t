use Rum;
use Test::More;


#This test ensures SourceStream.pipe(DestStream) returns DestStream

my $Stream = Require('stream');
my $assert = Require('assert');
my $util = Require('util');

my $sourceStream = $Stream->new();
my $destStream = $Stream->new();
my $result = $sourceStream->pipe($destStream);

is($result, $destStream);

done_testing();

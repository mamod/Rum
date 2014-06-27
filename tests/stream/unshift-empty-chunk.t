use Rum;
use Test::More;

#This test verifies that stream.unshift(Buffer(0)) or 
#stream.unshift('') does not set state.reading=false.
my $Readable = Require('stream')->Readable;

my $r = $Readable->new();
my $nChunks = 10;
my $chunk = Buffer->new(10);
$chunk->fill('x');

$r->{_read} = sub {
    my ($n) = @_;
    setTimeout( sub {
        $r->push(--$nChunks == 0 ? undef : $chunk);
    });
};

my $readAll = 0;
my $seen = [];
$r->on('readable', sub {
    my $chunk;
    while ($chunk = $r->read()) {
        push @{ $seen }, $chunk->toString();
        #simulate only reading a certain amount of the data,
        #and then putting the rest of the chunk back into the
        #stream, like a parser might do.  We just fill it with
        #'y' so that it's easy to see which bits were touched,
        #and which were not.
        my $putBack = Buffer->new($readAll ? 0 : 5);
        $putBack->fill('y');
        $readAll = !$readAll;
        $r->unshift($putBack);
    }
});

my $expect =
  [ 'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy',
    'xxxxxxxxxx',
    'yyyyy' ];

$r->on('end', sub {
    is_deeply($seen, $expect);
    done_testing();
});

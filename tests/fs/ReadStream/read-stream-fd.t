use Rum;
use Test::More;

my $fs = Require('fs');
my $assert = Require('assert');
my $path = Require('path');

my $common = Require('../../common');

my $file = $path->join($common->{tmpDir}, '/read_stream_fd_test.txt');
my $input = 'hello world';
my $output = '';
my $fd;
my $stream;

$fs->writeFileSync($file, $input);
$fd = $fs->openSync($file, 'r');

$stream = $fs->createReadStream(undef, { fd => $fd, encoding => 'utf8' });
$stream->on('data', sub {
    my ($this,$data) = @_;
    $output .= $data;
});

process->on('exit', sub {
    unlink $file;
    is($output, $input);
    done_testing();
});

1;

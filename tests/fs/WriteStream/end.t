use Rum;
use Test::More;

my $common = Require('../../common');
my $assert = Require('assert');
my $path = Require('path');
my $fs = Require('fs');

{
    my $mustCalled = 0;
    my $file = $path->join($common->{tmpDir}, 'write-end-test0.txt');
    my $stream = $fs->createWriteStream($file);
    $stream->end();
    $stream->on('close', sub{
        ++$mustCalled;
    });
    
    process->on('exit', sub{
        is(1,$mustCalled);
    });
    
};

{
    my $file = $path->join($common->{tmpDir}, 'write-end-test1.txt');
    my $stream = $fs->createWriteStream($file);
    $stream->end("a\n", 'utf8');
    $stream->on('close', sub {
        my $content = $fs->readFileSync($file, 'utf8');
        is($content, "a\n");
    });
};

process->on('exit', sub{
    done_testing(2);
});

1;

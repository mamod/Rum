use Rum;
use Test::More;

my $common = Require('../../common');
my $assert = Require('assert');
my $fs = Require('fs');

test1($fs->createReadStream(__filename));
test2($fs->createReadStream(__filename));
test3($fs->createReadStream(__filename));

test1($fs->createWriteStream($common->{tmpDir} . '/dummy1'));
test2($fs->createWriteStream($common->{tmpDir} . '/dummy2'));
test3($fs->createWriteStream($common->{tmpDir} . '/dummy3'));

sub test1 {
    my ($stream) = @_;
    $stream->destroy();
    $stream->destroy();
}

sub test2 {
    my ($stream) = @_;
    my $open_cb_called = 0;
    $stream->destroy();
    $stream->on('open', sub{
        my ($this,$fd) = @_;
        $stream->destroy();
        $open_cb_called++;
    });
    process->on('exit', sub{
        is($open_cb_called, 1);
    });
}

sub test3 {
    my ($stream) = @_;
    my $open_cb_called = 0;
    $stream->on('open', sub {
        $stream->destroy();
        $stream->destroy();
        $open_cb_called++;
    });
    
    process->on('exit', sub{
        is($open_cb_called, 1);
    });
}

process->on('exit', sub{
    done_testing();
});

1;

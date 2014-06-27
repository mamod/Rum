use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $path = Require('path');
my $Buffer = Require('buffer')->{Buffer};
my $fs = Require('fs');
my $filename = $path->join($common->{tmpDir}, 'write.txt');
my $expected = $Buffer->new('hello');
my $openCalled = 0;
my $writeCalled = 0;

$fs->open($filename, 'w', 0644, sub {
    my ($err, $fd) = @_;
    $openCalled++;
    die $err if $err;

    $fs->write($fd, $expected, 0, $expected->length, undef, sub {
        my ($err, $written) = @_;
        $writeCalled++;
        die $err if $err;
        is($expected->length, $written);
        $fs->closeSync($fd);
        my $found = $fs->readFileSync($filename, 'utf8');
        is($expected->toString(), $found);
        unlink($filename);
    });
});

process->on('exit', sub {
    is(1, $openCalled);
    is(1, $writeCalled);
    done_testing();
});

1;

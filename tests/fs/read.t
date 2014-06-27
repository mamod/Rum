use Rum;
use Test::More;
my $common = Require('../common');
my $assert = Require('assert');
my $path = Require('path');
my $fs = Require('fs');
my $filepath = $path->join($common->{fixturesDir}, 'x.txt');
my $fd = $fs->openSync($filepath, 'r');
my $expected = "xyz\n";
my $readCalled = 0;

$fs->read($fd, length $expected, 0, 'utf-8', sub {
    my ($err, $str, $bytesRead) = @_;
    $readCalled++;

    ok(!$err);
    is($str, $expected);
    is($bytesRead, length $expected);
});


my $r = $fs->readSync($fd, length $expected, 0, 'utf-8');
is($r->[0], $expected);
is ($r->[1], length $expected);

process->on('exit', sub {
    is($readCalled, 1);
    done_testing(6);
});


1;

use Rum;
use Data::Dumper;
use Test::More;

my $common = Require('../../common');
my $path = Require('path');
my $fs = Require('fs');


my $readEmit = 0;
my $emptyFile = $path->join($common->{fixturesDir}, 'empty.txt');
$fs->open($emptyFile, 'r', sub {
    my ($error, $fd)  = @_;
    die $error if $error;
    my $read = $fs->createReadStream($emptyFile, { 'fd' => $fd });
    
    $read->once('data', sub {
        die('data event should not emit');
    });
    
    $read->once('end', sub {
        $readEmit = 1;
        #diag('end event 1');
    });
});

process->on('exit', sub {
    is($readEmit, 1);
    done_testing(1);
});

1;

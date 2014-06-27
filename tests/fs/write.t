use Rum;
use Test::More;
use FileHandle;

my $common = Require('../common');
my $assert = Require('assert');
my $path = Require('path');
my $Buffer = Require('buffer').Buffer;
my $fs = Require('fs');
my $fn = $path->join($common->{tmpDir}, 'write.txt');
my $fn2 = $path->join($common->{tmpDir}, 'write2.txt');
my $expected = 'ümlaut.';
#my $constants = require('constants');
my $found;
my $found2;

$fs->open($fn, 'w', 0644, sub {
    my ($err, $fd) = @_;
    die $err if ($err);
    #console.log('open done');
    $fs->write($fd, '', 0, 'utf8', sub {
        my ($err, $written) = @_;
        $assert->equal(0, $written);
    });
    
    $fs->write($fd, $expected, 0, 'utf8', sub {
        my ($err, $written) = @_;
        #console.log('write done');
        die $err if ($err);
        $assert->equal(bytes::length($expected), $written);
        $fs->closeSync($fd);
        $found = $fs->readFileSync($fn, 'utf8');
        unlink($fn);
    });
});


$fs->open($fn2, O_CREAT | O_WRONLY | O_TRUNC, 0644,
    sub {
        my ($err, $fd) = @_;
        die $err if ($err);
        #console.log('open done');
        $fs->write($fd, '', 0, 'utf8', sub {
            my ($err, $written) = @_;
            is(0, $written);
        });
        
        $fs->write($fd, $expected, 0, 'utf8', sub {
            my ($err, $written) = @_;
            #console.log('write done');
            die $err if ($err);
            is( bytes::length($expected), $written);
            $fs->closeSync($fd);
            $found2 = $fs->readFileSync($fn2, 'utf8');
            unlink $fn2;
        });
    }
);


process->on('exit', sub{
    is($expected, $found);
    is($expected, $found2);
    done_testing(4);
});

1;

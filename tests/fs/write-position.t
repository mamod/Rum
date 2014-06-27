use Rum;
use Test::More;
my $common = Require('../common');
my $path = Require('path');
my $fs = Require('fs');

my $file = $path->join($common->{tmpDir}, 'write-position.txt');

my $buff = Buffer->new("Hi there",'utf8');
my $fd = $fs->openSync($file, 'w');

$fs->write($fd,$buff,0,2,0,sub{
    my ($err,$bytesWritten) = @_;
    die $err if $err;
    
    my $buffer = $fs->readFileSync($file);
    is($bytesWritten,2);
    is($buffer->get(0), 72);
    is($buffer->get(1), 105);
    is($buffer->toString(), "Hi");
    
    ##same story
    $fs->write($fd,$buff,0,2,0,sub{
        my ($err,$bytesWritten) = @_;
        die $err if $err;
        my $buffer = $fs->readFileSync($file);
        is($bytesWritten,2);
        is($buffer->get(0), 72);
        is($buffer->get(1), 105);
        is($buffer->toString(), "Hi");
        
        ##write all
        $fs->write($fd,$buff,2,6,2,sub{
            my ($err,$bytesWritten) = @_;
            die $err if $err;
            
            my $buffer = $fs->readFileSync($file);
            is($bytesWritten,6);
            is($buffer->get(0), 72); #H
            is($buffer->get(1), 105); #i
            is($buffer->get(2), 32); #space
            is($buffer->get(3), 116); #t
            is($buffer->get(4), 104); #h
            is($buffer->get(5), 101); #e
            is($buffer->get(6), 114); #r
            is($buffer->get(7), 101); #e
            is($buffer->toString(), "Hi there");
            
            #close
            $fs->closeSync($fd);
        });
    });
});


##sync version
{
    
    my $file2 = $path->join($common->{tmpDir}, 'write-position-sync.txt');
    my $buff = Buffer->new("Hi there",'utf8');
    my $fd = $fs->openSync($file2, 'w');

    my $bytesWritten = $fs->writeSync($fd,$buff,0,2,0,);
    my $buffer = $fs->readFileSync($file2);
    is($bytesWritten,2);
    is($buffer->get(0), 72);
    is($buffer->get(1), 105);
    is($buffer->toString(), "Hi");
    
    $bytesWritten = $fs->writeSync($fd,$buff,2,6,2);
    $buffer = $fs->readFileSync($file2);
    is($bytesWritten,6);
    is($buffer->get(0), 72); #H
    is($buffer->get(1), 105); #i
    is($buffer->get(2), 32); #space
    is($buffer->get(3), 116); #t
    is($buffer->get(4), 104); #h
    is($buffer->get(5), 101); #e
    is($buffer->get(6), 114); #r
    is($buffer->get(7), 101); #e
    is($buffer->toString(), "Hi there");
    $fs->closeSync($fd);
    unlink $file2;
}


process->on('exit',sub{
    unlink $file;
    done_testing(32);
});

1;

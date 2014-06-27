use Rum;
use Test::More;

my $common = Require('../common');
my $path = Require('path');

my $filepath = $path->join($common->{fixturesDir}, 'hi.txt');

my $fs = Require('fs');

my $fd = $fs->openSync($filepath,'r');
my $buf = Buffer->new(9);
$fs->read($fd,$buf,0,2,0,sub{
    my ($err, $bytesRead, $buffer) = @_;
    is($bytesRead,2);
    is($buffer->get(0), 72);
    is($buffer->get(1), 105);
    is($buffer->toString(), "Hi");
    ##should give same results
    $fs->read($fd,$buf,0,2,0,sub{
        my ($err, $bytesRead, $buffer) = @_;
        is($bytesRead,2);
        is($buffer->get(0), 72); #H
        is($buffer->get(1), 105); #i
        is($buffer->toString(), "Hi");
        
        ##read the rest
        $fs->read($fd,$buf,2,6,2,sub {
            my ($err, $bytesRead, $buffer) = @_;
            is($bytesRead,6);
            is($buffer->get(0), 72); #H
            is($buffer->get(1), 105); #i
            is($buffer->get(2), 32); #space
            is($buffer->get(3), 116); #t
            is($buffer->get(4), 104); #h
            is($buffer->get(5), 101); #e
            is($buffer->get(6), 114); #r
            is($buffer->get(7), 101); #e
            
            is($buffer->toString(), "Hi there");
            #diag $buffer->toString();
            
            ##get file handle from fd
            my $fh = $fs->fh($fd);
            
            $fs->close($fd,sub{
                my ($err) = @_;
                die $err if $err;
                {
                    ##make sure file handle closed
                    no warnings;
                    ok(tell($fh) == -1);
                    ok(!$fs->fh($fd));
                }
            });
            
        });
        
    });
});

##sync interface
{
    my $fd = $fs->openSync($filepath,'r');
    my $buffer = Buffer->new(9);
    my $bytesRead = $fs->readSync($fd,$buffer,0,2,0);
    
    is($bytesRead,2);
    is($buffer->get(0), 72); #H
    is($buffer->get(1), 105); #i
    is($buffer->toString(), "Hi");
    
    #again
    $bytesRead = $fs->readSync($fd,$buffer,0,2,0);
    is($bytesRead,2);
    is($buffer->get(0), 72); #H
    is($buffer->get(1), 105); #i
    is($buffer->toString(), "Hi");
    
    ##read all
    $bytesRead = $fs->readSync($fd,$buffer,2,6,2);
    is($bytesRead,6);
    is($buffer->get(0), 72); #H
    is($buffer->get(1), 105); #i
    is($buffer->get(2), 32); #space
    is($buffer->get(3), 116); #t
    is($buffer->get(4), 104); #h
    is($buffer->get(5), 101); #e
    is($buffer->get(6), 114); #r
    is($buffer->get(7), 101); #e
    is($buffer->toString(), "Hi there");
    
    ##did we close it properly
    my $fh = $fs->fh($fd);
    $fs->closeSync($fd);
    {
        no warnings;
        ok(tell($fh) == -1);
        ok(!$fs->fh($fd));
    }
}

process->on('exit',sub{
    done_testing(40);
});

1;

use Rum;
use Test::More;
my $common = Require('../common');

my $assert = Require('assert');
my $net = Require('net');

my $N = 200;
my $recv;
my $chars_recved = 0;

my $server = $net->createServer( sub {
    my $this = shift;
    my $connection = shift;
    my $write; $write = sub {
        my $j = shift;
        
        my $t;
        if ($j >= $N) {
            
            $connection->end();
            return;
        }
        
        $t = setTimeout(sub {
            $connection->write('C');
            $write->($j + 1);
        }, 10);
    };
    $write->(0);
});

$server->on('listening', sub {
    
    my $client = $net->createConnection($common->{PORT});
    $client->setEncoding('ascii');
    
    $client->on('data',sub {
        my $this = shift;
        my $d = shift;
        diag( $d );
        $recv .= $d;
    });
    
    setTimeout( sub {
        $chars_recved = length $recv;
        diag('pause at: ' . $chars_recved);
        ok($chars_recved > 1);
        $client->pause();
        setTimeout(sub {
            diag('resume at: ' . $chars_recved );
            is($chars_recved, length $recv);
            $client->resume();
            
            setTimeout(sub {
                $chars_recved = length $recv;
                diag('pause at: ' . $chars_recved);
                $client->pause();
                
                setTimeout(sub {
                    diag('resume at: ' . $chars_recved);
                    is($chars_recved, length $recv);
                    $client->resume();
                    
                }, 500);
                
            }, 500);
        }, 500);
    }, 500);
    
    $client->on('end', sub {
        $server->close();
        $client->end();
    });
    
    $client->on('error', sub {
        shift;
        fail('should not get any error');
    });
    
});

$server->listen($common->{PORT});

process->on('exit', sub {
    is($N, length $recv);
    #common.debug('Exit');
    done_testing();
});

1;

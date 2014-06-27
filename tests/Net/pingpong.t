use Rum;
use Data::Dumper;
use Test::More;

sub debug {
    diag $_[0];
}
my $common = Require('../common');
my $assert = Require('assert');
my $net = Require('net');

my $tests_run = 0;

use Data::Dumper;

sub pingPongTest {
    my ($port, $host, $on_complete) = @_;
    my $N = 100;
    my $DELAY = 1;
    my $count = 0;
    my $client_ended = 0;
    
    my $server = $net->createServer({ allowHalfOpen => 1 }, sub {
        my $this = shift;
        my $socket = shift;
        $socket->setEncoding('utf8');
        
        $socket->on('data', sub {
            my $this = shift;
            my $data = shift;
            debug($data);
            is('PING', $data);
            is('open', $socket->readyState);
            ok($count <= $N);
            setTimeout(sub {
                
                is('open', $socket->readyState);
                $socket->write('PONG');
            }, $DELAY);
        });
        
        $socket->on('timeout', sub {
            debug('server-side timeout!!');
            is(0, 1);
        });
        
        $socket->on('end', sub {
            debug('server-side socket EOF');
            is('writeOnly', $socket->readyState);
            $socket->end();
        });
        
        $socket->on('close', sub {
            my $this = shift;
            my $had_error = shift;
            debug('server-side socket.end');
            ok(!$had_error);
            is('closed', $socket->readyState);
            $socket->{server}->close();
        });
    });
    
    $server->listen($port, $host, sub {
        my $client = $net->createConnection($port, $host);
        
        $client->setEncoding('utf8');
        
        $client->on('connect', sub {
            is('open', $client->readyState);
            $client->write('PING');
        });
        
        $client->on('data', sub {
            
            my $this = shift;
            my $data = shift;
            debug($data);
            is('PONG', $data);
            is('open', $client->readyState);
            
            setTimeout(sub {
                is('open', $client->readyState);
                
                if ($count++ < $N) {
                    $client->write('PING');
                } else {
                    debug('closing client');
                    $client->end();
                    $client_ended = 1;
                }
            }, $DELAY);
        });
        
        $client->on('timeout', sub {
            debug('client-side timeout!!');
        });
        
        $client->on('close', sub {
            debug('client.end');
            is($N + 1, $count);
            ok($client_ended);
            if ($on_complete) { on_complete() };
            $tests_run += 1;
        });
    });
}

pingPongTest($common->{PORT});

process->on('exit', sub {
    is(1, $tests_run);
    done_testing();
});

1;

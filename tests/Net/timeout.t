use Rum;
use Time::HiRes qw(time);
use Test::More;



sub debug {
    diag $_[0];
}

sub now {
    return int( time() * 1000 );
}

my $common = Require('../common');
my $net = Require('net');

my $exchanges = 0;
my $starttime = -1;
my $timeouttime = -1;
my $timeout = 1000;

my $echo_server;  $echo_server = $net->createServer( sub {
    my $this = shift;
    my $socket = shift;
    $socket->setTimeout($timeout);
    
    $socket->on('timeout', sub {
        debug('server timeout');
        $timeouttime = now();
        debug($timeouttime);
        $socket->destroy();
    });

    $socket->on('error', sub {
        die('Server side socket should not get error. ' .
                      'We disconnect willingly.');
    });

    $socket->on('data', sub {
        my $this = shift;
        my $d = shift;
        debug($d);
        $socket->write($d);
    });

    $socket->on('end', sub {
        $socket->end();
    });
});

$echo_server->listen($common->{PORT}, sub {
    debug('server listening at ' . $common->{PORT});

    my $client = $net->createConnection($common->{PORT});
    $client->setEncoding('UTF8');
    $client->setTimeout(0); # disable the timeout for client
    $client->on('connect', sub {
        debug('client connected.');
        $client->write("hello\n");
    });

    $client->on('data', sub {
        my $this = shift;
        my $chunk = shift;
        is("hello\n", $chunk);
        if ($exchanges++ < 5) {
            setTimeout( sub {
                debug('client write "hello"');
                $client->write("hello\n");
            }, 500);

            if ($exchanges == 5) {
                debug('wait for timeout - should come in ' . $timeout . ' ms');
                $starttime = now();
                debug($starttime);
            }
        }
    });

    $client->on('timeout', sub {
        die("client timeout - this shouldn't happen");
    });

    $client->on('end', sub {
        debug('client end');
        $client->end();
    });

    $client->on('close', sub {
        debug('client disconnect');
        $echo_server->close();
    });
});

process->on('exit', sub {
    ok($starttime != -1, '$starttime != -1');
    ok($timeouttime != -1, '$timeouttime != -1');
    
    my $diff = $timeouttime - $starttime;
    debug('diff = ' . $diff);
    
    ok($timeout < $diff, '$timeout < $diff');
    
    #Allow for 800 milliseconds more
    ok($diff < $timeout + 800, '$diff < $timeout + 800');
    
    done_testing();
    
});

1;

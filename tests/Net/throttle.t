use Rum;
use Data::Dumper;
use Test::More;

my $common = Require('../common');

sub debug {
    diag $_[0];
}

my $assert = Require('assert');
my $net = Require('net');

my $N = 1024 * 1024;
my $part_N =  $N / 3;
my $chars_recved = 0;
my $npauses = 0;

debug('build big string');

my $body = '';
for (my $i = 0; $i < $N; $i++) {
    $body .= 'c';
}

debug('start server on port ' . $common->{PORT});

my $server = $net->createServer( sub {
    my $this = shift;
    my $connection = shift;
    
    $connection->on('error', sub {
        shift;
        my $e = shift;
        fail('should not get any error');
    });
    
    $connection->write(substr($body, 0, $part_N));
    $connection->write(substr($body, $part_N * 2, $part_N));
    $connection->write(substr($body,2 * $part_N, $N));
    
    for (0..60){
        $connection->write('a');
        $N++;
    }
    
    debug('bufferSize: ' . $connection->bufferSize . ' expecting ' . $N);
    
    ok(0 <= $connection->bufferSize && $connection->{_writableState}->{length} <= $N);
    $connection->end();
});

$server->listen($common->{PORT}, sub {
    my $paused = 0;
    my $client = $net->createConnection($common->{PORT});
    $client->setEncoding('ascii');
    $client->on('data', sub {
        my $this = shift;
        my $d = shift;
        $chars_recved += length $d;
        
        debug('got ' . $chars_recved);
        if (!$paused) {
            $client->pause();
            $npauses += 1;
            $paused = 1;
            debug('pause');
            my $x = $chars_recved;
            setTimeout( sub {
                is($chars_recved, $x);
                $client->resume();
                debug('resume');
                $paused = 0;
            }, 100);
        }
    });

    $client->on('end', sub {
        $server->close();
        $client->end();
    });
    
    $client->on('error', sub {
        shift;
        fail('should not get any error');
    });
    
});



process->on('exit', sub {
    is($N, $chars_recved);
    ok($npauses > 2);
    done_testing();
});


1;

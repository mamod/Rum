use Rum;
use Test::More;


my $common = Require('../common');

my $assert = Require('assert');
my $net = Require('net');

my $seconds = 5;
my $gotTimeout = 0;
my $counter = 0;

my $server; $server = $net->createServer( sub {
    my $this = shift;
    my $socket = shift;
    $socket->setTimeout(($seconds / 2) * 1000, sub {
        $gotTimeout = 1;
        debug('timeout!!');
        $socket->destroy();
        process->exit(1);
    });

    my $interval; $interval = setInterval( sub {
        $counter++;
        
        if ($counter == $seconds) {
            clearInterval($interval);
            $server->close();
            $socket->destroy();
        }
        
        if ($socket->{writable}) {
            $socket->write("#" . time() . "\n");
        }
    }, 1000);
});


$server->listen($common->{PORT}, sub {
    my $s = $net->connect($common->{PORT});
    #$s->pipe(process->stdout);
});


process->on('exit', sub {
    is(0, $gotTimeout);
    done_testing();
});

1;

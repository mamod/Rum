use Rum;
use Test::More;

my $common = Require('../common');
my $net = Require('net');
my $assert = Require('assert');

my $cbcount = 0;

##TODO : raise this value to 500000
my $N = 5000;

my $server; $server = $net->Server( sub {
    my $self = shift;
    my $socket = shift;
    $socket->on('data', sub {
        my $this = shift;
        my $d = shift;
        diag(sprintf("got %d bytes\n", $d->length));
    });

    $socket->on('end', sub{
        diag('end');
        $socket->destroy();
        $server->close();
    });
});

my $lastCalled = -1;
sub makeCallback {
    my $c = shift;
    my $called = 0;
    return sub {
        if ($called) {
            fail('called callback #' . $c . ' more than once');
        }
        $called = 1;
        if ($c < $lastCalled) {
            fail('callbacks out of order. last=' . $lastCalled .
                      ' current=' . $c);
        }
        $lastCalled = $c;
        $cbcount++;
    };
}

$server->listen($common->{PORT}, sub {
    my $client = $net->createConnection($common->{PORT});

    $client->on('connect', sub {
        for (my $i = 0; $i < $N; $i++) {
            $client->write('hello world', makeCallback($i));
        }
        $client->end();
    });
});

process->on('exit', sub {
    is($N, $cbcount);
    done_testing();
});

1;


##Rum echo server
# >perl runner.pl ./examples/echo-server.pl

use Rum;

my $net = Require('net');
my $server = $net->createServer( sub { #'connection' listener
    my $this = shift;
    my $c = shift;
    print('server connected' . "\n");
    $c->on('end', sub {
        print('server disconnected' . "\n");
    });
    $c->pipe($c);
});

$server->listen(9090, sub { #'listening' listener
    print('server bound' . "\n");
});

1;

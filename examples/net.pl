# > perl runner.pl ./net.pl
# - then
# > telnet localhost 9090

use Rum;
use Data::Dumper;

my $net = Require('net');

sub debug {
    print $_[0] . "\n";
}

my $server; $server = $net->createServer( sub { #'connection' listener
    my $this = shift;
    my $c = shift;
    debug('server connected');
    
    $c->on('end', sub {
        debug('server disconnected');
    });
    
    $c->on('error', sub{
        my $this = shift;
        my $e = shift;
        print "Got Error\n";
        $e->throw();
    });
    
    $c->write("hello\r\n");
    $c->pipe($c)->pipe($c)->pipe($c)->pipe($c)->pipe($c);
    
});

$server->on('error', sub {
    my $this = shift;
    my $e = shift;
    print "Got Error\n";
    $e->throw();
});

$server->listen(9090, sub {
    #'listening' listener
    debug("server bound");
});

1;

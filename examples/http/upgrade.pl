use Rum;
my $http = Require('http');

#Create an HTTP server
my $srv = $http->createServer( sub {
    my ($req, $res) = @_;
    $res->writeHead(200, {'Content-Type' => 'text/plain'});
    $res->end('okay');
});

$srv->on('upgrade', sub {
    my ($this, $req, $socket, $head) = @_;
    $socket->write("HTTP/1.1 101 Web Socket Protocol Handshake\r\n" .
               "Upgrade: WebSocket\r\n" .
               "Connection: Upgrade\r\n" .
               "\r\n");
    
    $socket->pipe($socket); # echo back
});


$srv->listen(1437, '127.0.0.1', sub {
    print "Server listening", "\n";
    #make a request
    my $options = {
        port => 1437,
        hostname => '127.0.0.1',
        headers => {
            'Connection' => 'Upgrade',
            'Upgrade' => 'websocket'
        }
    };
    
    my $req = $http->request($options);
    $req->end();
    
    $req->on('upgrade', sub {
        my ($this, $res, $socket, $upgradeHead) = @_;
        print "got upgraded!", "\n";
        $socket->end();
        exit;
    });
});

1;

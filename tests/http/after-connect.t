use Rum;
use Test::More;
use Data::Dumper;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');

my $serverConnected = 0;
my $serverRequests = 0;
my $clientResponses = 0;

my $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    print('Server got GET request', "\n");
    $req->resume();
    ++$serverRequests;
    $res->writeHead(200);
    $res->write('');
    setTimeout( sub {
        $res->end($req->{url});
    }, 50);
});

$server->on('connect', sub  {
    my ($this, $req, $socket, $firstBodyChunk) = @_;
    print('Server got CONNECT request', "\n");
    $serverConnected = 1;
    $socket->write("HTTP/1.1 200 Connection established\r\n\r\n");
    $socket->resume();
    $socket->on('end', sub {
        $socket->end();
    });
});

$server->listen($common->{PORT}, sub {
    my $req = $http->request({
        port => $common->{PORT},
        method => 'CONNECT',
        path => 'google.com:80'
    });
    
    $req->on('connect', sub {
        my ($this, $res, $socket, $firstBodyChunk) = @_;
        print('Client got CONNECT response', "\n");
        $socket->end();
        $socket->on('end', sub {
            doRequest(0);
            doRequest(1);
        });
        $socket->resume();
    });
    $req->end();
});

sub doRequest {
    my $i = shift;
    my $req = $http->get({
        port => $common->{PORT},
        path => '/request' . $i
    }, sub {
        my ($this, $res) = @_;
        print('Client got GET response', "\n");
        my $data = '';
        $res->setEncoding('utf8');
        $res->on('data', sub {
            my ($this, $chunk) = @_;
            $data .= $chunk;
        });
        $res->on('end', sub {
            is($data, '/request' . $i);
            ++$clientResponses;
            if ($clientResponses == 2) {
                $server->close();
            }
        });
    });
}

process->on('exit', sub {
    ok($serverConnected);
    is($serverRequests, 2);
    is($clientResponses, 2);
    done_testing();
});

1;

use Rum;
use Test::More;
use Data::Dumper;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');
my $net = Require('net');

my $gotReq = 0;

my $server = $http->createServer(sub {
    my ($this, $req, $res) = @_;
    print('got req', "\n");
    $gotReq = 1;
    is('GET', $req->{method});
    is('/blah', $req->{url});
    print Dumper $req->{headers};
    is_deeply({
        host => 'mapdevel.trolologames.ru:443',
        origin => 'http://mapdevel.trolologames.ru',
        cookie => ''
    }, $req->{headers});
});

$server->listen($common->{PORT}, sub {
    my $c = $net->createConnection($common->{PORT});
    
    $c->on('connect', sub {
        print('client wrote message', "\n");
        $c->write("GET /blah HTTP/1.1\r\n" .
            "Host: mapdevel.trolologames.ru:443\r\n" .
            "Cookie:\r\n" .
            "Origin: http://mapdevel.trolologames.ru\r\n" .
            "\r\n\r\nhello world"
        );
    });
    
    $c->on('end', sub {
        $c->end();
    });
    
    $c->on('close', sub {
        print('client close', "\n");
        $server->close();
    });
});

process->on('exit', sub {
    ok($gotReq);
    done_testing();
});

1;

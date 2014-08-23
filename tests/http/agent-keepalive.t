use Rum;
use Rum::HTTP::Agent;
use Test::More;
use Data::Dumper;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');
#my $Agent = Require('_http_agent');
#var EventEmitter = require('events').EventEmitter;

my $agent = Rum::HTTP::Agent->new({
    keepAlive => 1,
    keepAliveMsecs => 1000,
    maxSockets => 5,
    maxFreeSockets => 5
});

my $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    if ($req->{url} eq '/error') {
        $res->destroy();
        return;
    } elsif ($req->{url} eq '/remote_close') {
        # cache the socket, close it after 100ms
        my $socket = $res->{connection};
        setTimeout(sub {
            $socket->end();
        }, 100);
    }
    $res->end('hello world');
});

sub get {
    my ($path, $callback) = @_;
    return $http->get({
        host => 'localhost',
        port => $common->{PORT},
        agent => $agent,
        path => $path
    }, $callback);
}

my $name = 'localhost:' . $common->{PORT} . '::';

sub checkDataAndSockets {
    my ($this, $body) = @_;
    is($body->toString(), 'hello world');
    is(@{$agent->{sockets}->{$name}}, 1);
    ok(!$agent->{freeSockets}->{$name});
}

sub second {
    # request second, use the same socket
    get('/second', sub {
        my ($this, $res) = @_;
        is($res->{statusCode}, 200);
        $res->on('data', \&checkDataAndSockets);
        $res->on('end', sub {
            is(@{$agent->{sockets}->{$name}}, 1);
            ok(!$agent->{freeSockets}->{$name});
            process->nextTick( sub {
                ok(!$agent->{sockets}->{$name});
                is(@{$agent->{freeSockets}->{$name}}, 1);
                remoteClose();
            });
        });
    });
}

sub remoteClose() {
    # mock remote server close the socket
    get('/remote_close', sub {
        my ($this, $res) = @_;
        is($res->{statusCode}, 200);
        $res->on('data', \&checkDataAndSockets);
        $res->on('end', sub {
            is(@{$agent->{sockets}->{$name}}, 1);
            ok(!$agent->{freeSockets}->{$name});
            process->nextTick( sub {
                ok(!$agent->{sockets}->{$name});
                is(@{$agent->{freeSockets}->{$name}}, 1);
                # waitting remote server close the socket
                setTimeout( sub {
                    ok(!$agent->{sockets}->{$name});
                    ok(!$agent->{freeSockets}->{$name},'freeSockets is not empty');
                    remoteError();
                }, 200);
            });
        });
    });
}

sub remoteError() {
    # remove server will destroy ths socket
    my $req = get('/error', sub {
        my ($this, $res) = @_;
        Error->new('should not call this function')->throw;
    });
    
    $req->on('error', sub {
        my ($this, $err) = @_;
        ok($err);
        is($err->{message}, 'socket hang up');
        is(@{$agent->{sockets}->{$name}}, 1);
        ok(!$agent->{freeSockets}->{$name});
        # Wait socket 'close' event emit
        setTimeout( sub {
            ok(!$agent->{sockets}->{$name});
            ok(!$agent->{freeSockets}->{$name});
            done();
        }, 1);
    });
}

sub done() {
    print('http keepalive agent test success.', "\n");
    done_testing();
    exit(0);
}

$server->listen($common->{PORT}, sub {
    # request first, and keep alive
    get('/first', sub {
        my ($this, $res) = @_;
        is($res->{statusCode}, 200);
        $res->on('data', \&checkDataAndSockets);
        $res->on('end', sub {
            is(@{$agent->{sockets}->{$name}}, 1);
            ok(!$agent->{freeSockets}->{$name});
            process->nextTick( sub {
                ok(!$agent->{sockets}->{$name});
                is(@{$agent->{freeSockets}->{$name}}, 1);
                second();
            });
        });
    });
});

1;

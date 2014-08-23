use Rum;
use Test::More;
use Data::Dumper;


my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');

sub debug {
    print @_, "\n";
}

my $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    $res->writeHead(200, {'Content-Type' => 'text/plain'});
    $res->end("Hello World\n");
})->listen($common->{PORT});

my $agent = $http->{Agent}->new({maxSockets => 1});

$agent->on('free', sub {
    my ($this, $socket, $host, $port) = @_;
    debug('freeing socket. destroyed? ', $socket->{destroyed});
});

my $requestOptions = {
    agent => $agent,
    host => 'localhost',
    port => $common->{PORT},
    path => '/'
};

my $request2;
my $request1; $request1 = $http->get($requestOptions, sub {
    my ($this, $response) = @_;
    
    #assert request2 is queued in the agent
    my $key = $agent->getName($requestOptions);
    ok(@{$agent->{requests}->{$key}} == 1);
    debug('got response1');
    $request1->{socket}->on('close', sub {
        debug('request1 socket closed');
    });
    
    $response->pipe(process->stdout);
    $response->on('end', sub {
        debug('response1 done');
        #/////////////////////////////////
        #//
        #// THE IMPORTANT PART
        #//
        #// It is possible for the socket to get destroyed and other work
        #// to run before the 'close' event fires because it happens on
        #// nextTick. This example is contrived because it destroys the
        #// socket manually at just the right time, but at Voxer we have
        #// seen cases where the socket is destroyed by non-user code
        #// then handed out again by an agent *before* the 'close' event
        #// is triggered.
        $request1->{socket}->destroy();
        
        $response->once('close', sub {
            #assert request2 was removed from the queue
            ok(!$agent->{requests}->{$key});
            debug("waiting for request2.onSocket's nextTick");
            process->nextTick( sub {
                #assert that the same socket was not assigned to request2,
                #since it was destroyed.
                ok($request1->{socket} != $request2->{socket});
                ok(!$request2->{socket}->{destroyed}, 'the socket is destroyed');
            });
        });
    });
});


my $gotClose = 0;
my $gotResponseEnd = 0;
$request2 = $http->get($requestOptions, sub {
    my ($this, $response) = @_;
    ok(!$request2->{socket}->{destroyed});
    ok($request1->{socket}->{destroyed});
    # assert not reusing the same socket, since it was destroyed.
    ok($request1->{socket} != $request2->{socket});
    debug('got response2');
    
    $request2->{socket}->on('close', sub {
        debug('request2 socket closed');
        $gotClose = 1;
        done();
    });
    
    $response->pipe(process->stdout);
    $response->on('end', sub {
        debug('response2 done');
        $gotResponseEnd = 1;
        done();
    });
});

sub done {
    if ($gotResponseEnd && $gotClose) {
        $server->close();
    }
}


process->on('exit', sub {
    done_testing();
});

1;

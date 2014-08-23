use Rum;
use Data::Dumper;
use Test::More;

my $http = Require('http');
my $complete;

my $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    #We should not see the queued /thatotherone request within the server
    #as it should be aborted before it is sent.
    is($req->{url}, '/');
    
    $res->writeHead(200);
    $res->write('foo');
    
    $complete = $complete || sub {
        $res->end();
    };
});

$server->listen(0, sub {
    print('listen ', $server->address()->{port}, "\n");
    
    my $agent = $http->{Agent}->new({maxSockets => 1});
    is(keys %{$agent->{sockets}}, 0);
    
    my $options = {
        hostname => 'localhost',
        port => $server->address()->{port},
        method => 'GET',
        path => '/',
        agent => $agent
    };
    
    my $req1 = $http->request($options);
    $req1->on('response', sub {
        my ($this, $res1) = @_;
        is(keys(%{$agent->{sockets}}), 1);
        is(keys(%{$agent->{requests}}), 0);
        
        my $req2 = $http->request({
            method => 'GET',
            host => 'localhost',
            port => $server->address()->{port},
            path => '/thatotherone',
            agent => $agent
        });
        
        is(keys(%{$agent->{sockets}}), 1);
        is(keys(%{$agent->{requests}}), 1);
        
        $req2->on('error', sub {
            my ($this, $err) = @_;
            # This is expected in response to our explicit abort call
            is($err->{code}, 'ECONNRESET');
        });
        
        $req2->end();
        $req2->abort();
        
        is(keys(%{$agent->{sockets}}), 1);
        is(keys(%{$agent->{requests}}), 1);
        
        print('Got res: ' . $res1->{statusCode});
        print Dumper ($res1->{headers});
        
        $res1->on('data', sub {
            my ($this,$chunk) = @_;
            print('Read ' . $chunk->length . ' bytes' . "\n");
            printf(" chunk=%s\n", $chunk->toString());
            $complete->();
        });
        
        $res1->on('end', sub {
            print('Response ended.', "\n");
            
            setTimeout( sub {
                is(keys(%{$agent->{sockets}}), 0);
                is(keys(%{$agent->{requests}}), 0);
                
                $server->close();
            }, 100);
        });
    });
    
    $req1->end();
});

process->on('exit', sub {
    done_testing();
});

1;

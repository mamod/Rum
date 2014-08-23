use Rum;
use Test::More;
use Data::Dumper;

my $common = Require('../common');
my $http = Require('http');

my $server = $http->Server(sub {
    my ($this, $req, $res) = @_;
    print ('Server accepted request.' . "\n");
    $res->writeHead(200);
    $res->write('Part of my res.');
    
    $res->destroy();
});

my $responseClose = 0;

$server->listen($common->{PORT}, sub {
    my $client = $http->get({
        port => $common->{PORT},
        headers => { connection => 'keep-alive' }
    }, sub {
        my ($this,$res) = @_;
        
        $server->close();
        
        print('Got res: ' . $res->{statusCode} . "\n");
        #console.dir(res.headers);
        
        $res->on('data', sub {
            my ($this, $chunk) = @_;
            print('Read ' . $chunk->length . ' bytes' . "\n");
            printf(" chunk=%s\n", $chunk->toString());
        });
        
        $res->on('end', sub {
            print('Response ended.', "\n");
        });
        
        $res->on('aborted', sub {
            print('Response aborted.', "\n");
        });
        
        $res->{socket}->on('close', sub {
            print('socket closed, but not res', "\n");
        });
        
        # it would be nice if this worked:
        $res->on('close', sub {
            print('Response aborted', "\n");
            $responseClose = 1;
        });
    });
});

process->on('exit', sub {
    ok($responseClose);
    done_testing();
});

1;

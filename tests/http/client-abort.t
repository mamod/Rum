use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');

my $clientAborts = 0;
my $responses = 0;
my $N = 16;
my $requests = [];

sub debug {
    print $_[0], "\n";
}

my $server; $server = $http->Server(sub {
    my ($this, $req, $res) = @_;
    debug('Got connection');
    $res->writeHead(200);
    $res->write('Working on it...');
    
    #// I would expect an error event from req or res that the client aborted
    #// before completing the HTTP request / response cycle, or maybe a new
    #// event like "aborted" or something.
    
    $req->on('aborted', sub {
        $clientAborts++;
        debug('Got abort ' . $clientAborts);
        if ($clientAborts == $N) {
            debug('All aborts detected, you win.');
            $server->close();
        }
    });
    
    #// since there is already clientError, maybe that would be appropriate,
    #// since "error" is magical
    $req->on('clientError', sub {
        debug('Got clientError');
    });
});

$server->listen($common->{PORT}, sub {
    debug('Server listening.');
    
    for (my $i = 0; $i < $N; $i++) {
        debug('Making client ' . $i);
        my $options = { port => $common->{PORT}, path => '/?id=' . $i };
        my $req = $http->get($options, sub {
            my ($this, $res) = @_;
            debug('Client response code ' . $res->{statusCode});
            
            $res->resume();
            if (++$responses == $N) {
                debug('All clients connected, destroying.');
                foreach my $outReq (@{$requests}) {
                    debug('abort');
                    $outReq->abort();
                }
            }
        });
        
        push(@{$requests}, $req);
    }
});

process->on('exit', sub {
    is($N, $clientAborts);
    done_testing();
});

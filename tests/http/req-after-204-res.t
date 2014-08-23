use Rum;
use Test::More;

my $common = Require('../common');
my $http = Require('http');

# first 204 or 304 works, subsequent anything fails
my  $codes = [204, 200];

# Methods don't really matter, but we put in something realistic.
my $methods = ['DELETE', 'DELETE'];

my $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    my $code = shift @{$codes};
    ok($code && $code > 0);
    printf("writing %d response\n", $code);
    $res->writeHead($code, {});
    $res->end();
});

sub nextRequest {
    my $method = shift @{$methods};
    printf("writing request: %s\n", $method);
    
    my $request = $http->request({
        port =>  $common->{PORT},
        method => $method,
        path => '/'
    }, sub {
        my ($this, $response) =  @_;
        $response->on('end', sub {
            if (@{$methods} == 0) {
                print('close server', "\n");
                $server->close();
            } else {
                # throws error:
                nextRequest();
                # works just fine:
                #process.nextTick(nextRequest);
            }
        });
        $response->resume();
    });
    $request->end();
}

$server->listen($common->{PORT}, \&nextRequest);

process->on('exit', sub{
    done_testing();
});

1;

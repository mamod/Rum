use Rum;
use Test::More;

my $common = Require('../common');
my $http = Require('http');
my $net = Require('net');
my $request = 0;
my $response = 0;

process->on('exit', sub {
    is($request, 1, 'http server "request" callback was not called');
    is($response, 1, 'http request "response" callback was not called');
    done_testing();
});

my $server; $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    $request++;
    $res->end();
})->listen( sub {
    my $this = shift;
    my $options = {
        agent => undef,
        port => $this->address()->{port}
    };
    
    $http->get($options, sub {
        my $this = shift;
        my $res = shift;
        $response++;
        $res->resume();
        $server->close();
    });
});

1;

use Rum;
use Test::More;

my $common = Require('../common');
my $http = Require('http');
#my $url = Require('url');

my $request = 0;
my $response = 0;
process->on('exit', sub {
    is(1, $request, 'http server "request" callback was not called');
    is(1, $response, 'http client "response" callback was not called');
    done_testing();
});

my $server; $server = $http->createServer( sub {
    my ($this, $req, $res) = @_;
    $res->end();
    $request++;
})->listen($common->{PORT}, '127.0.0.1', sub {
    
    ##FIXME use URL parser instead
    #$opts = $url->parse('http://127.0.0.1:' . $common->{PORT} . '/');
    my $opts = { protocol => 'http:',
        slashes => 1,
        auth => undef,
        host => '127.0.0.1:' . $common->{PORT},
        port => $common->{PORT},
        hostname => '127.0.0.1',
        hash => undef,
        search => undef,
        query => undef,
        pathname => '/',
        path => '/',
        href => 'http://127.0.0.1:' . $common->{PORT} . '/'
    };
    
    #remove the `protocol` field… the `http` module should fall back
    #to "http:", as defined by the global, default `http.Agent` instance.
    $opts->{agent} = $http->{Agent}->new();
    $opts->{agent}->{protocol} = undef;
    
    $http->get($opts, sub {
        my ($this, $res) = @_;
        $response++;
        $res->resume();
        $server->close();
    });
});

1;

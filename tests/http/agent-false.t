use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');

# sending `agent: false` when `port: null` is also passed in (i.e. the result of
# a `url.parse()` call with the default port used, 80 or 443), should not result
# in an assertion error...
my $opts = {
    host => '127.0.0.1',
    port => undef,
    path => '/',
    method => 'GET',
    agent => undef
};

my $good = 0;
process->on('exit', sub {
    ok($good, 'expected either an "error" or "response" event');
    done_testing();
});

# we just want an "error" (no local HTTP server on port 80) or "response"
# to happen (user happens ot have HTTP server running on port 80). As long as the
# process doesn't crash from a C++ assertion then we're good.
my $req = $http->request($opts);
$req->on('response', sub {
    $good = 1;
});

$req->on('error', sub {
    # an "error" event is ok, don't crash the process
    $good = 1;
});

$req->end();

1;

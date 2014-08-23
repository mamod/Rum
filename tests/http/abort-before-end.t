use Rum;
use Test::More;

my $common = Require('../common');
my $http = Require('http');

my $server = $http->createServer( sub {  
    fail("should not be called");
});

$server->listen($common->{PORT}, sub {
    my $req = $http->request({method => 'GET', host => '127.0.0.1', port => $common->{PORT}});
    
    $req->on('error', sub {
        my ($this, $ex) = @_;
        #https://github.com/joyent/node/issues/1399#issuecomment-2597359
        #abort() should emit an Error, not the net.Socket object
        ok(ref $ex eq 'Rum::Error');
    });
    
    $req->abort();
    $req->end();
    $server->close();
});


process->on('exit', sub {
    ##on error may not be called at all if we get aborted while waiting
    ok(1); 
    done_testing();
});

1;

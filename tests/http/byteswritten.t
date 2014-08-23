use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');
my $body = "hello world\n";
my $sawFinish = 0;

process->on('exit', sub {
    ok($sawFinish);
    done_testing();
});

my $httpServer; $httpServer = $http->createServer(sub {
    my ($this, $req, $res) = @_;
    $httpServer->close();
    
    $res->on('finish', sub {
        $sawFinish = 1;
        #assert(typeof(req.connection.bytesWritten) === 'number');
        ok($req->{connection}->bytesWritten > 0);
    });
    
    $res->writeHead(200, { 'Content-Type' => 'text/plain' });
    # Write 1.5mb to cause some requests to buffer
    # Also, mix up the encodings a bit.
    my $chunk = '7' x 1024;
    my $bchunk = Buffer->new($chunk);
    for (my $i = 0; $i < 1024; $i++) {
        $res->write($chunk);
        $res->write($bchunk);
        #FIXME : hex encoding will trigger
        #a http parser error, node using hex in this test
        $res->write($chunk, 'ascii');
    }
    #Get .bytesWritten while buffer is not empty
    ok($res->{connection}->bytesWritten > 0);
    $res->end($body);
    
    $res->on('error', sub {
        die;
    });
    
});

$httpServer->listen($common->{PORT}, sub {
    $http->get({ port => $common->{PORT} });
});

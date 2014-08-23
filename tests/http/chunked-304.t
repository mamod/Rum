use Rum;
use Test::More;
use Data::Dumper;

my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');
my $net = Require('net');

#// RFC 2616, section 10.2.5:
#//
#//   The 204 response MUST NOT contain a message-body, and thus is always
#//   terminated by the first empty line after the header fields.
#//
#// Likewise for 304 responses. Verify that no empty chunk is sent when
#// the user explicitly sets a Transfer-Encoding header.

test(204, sub {
  test(304);
});

sub test {
    my ($statusCode, $next) = @_;
    my $server; $server = $http->createServer(sub {
        my ($this, $req, $res) = @_;
        $res->writeHead($statusCode, { 'Transfer-Encoding' => 'chunked' });
        $res->end();
        $server->close();
    });
    
    $server->listen($common->{PORT}, sub {
        my $conn; $conn = $net->createConnection($common->{PORT}, sub {
            $conn->write("GET / HTTP/1.1\r\n\r\n");
            
            my $resp = '';
            $conn->setEncoding('utf8');
            $conn->on('data', sub {
                my ($this, $data) = @_;
                $resp .= $data;
            });
            
            $conn->on('end', $common->mustCall(sub {
                ok($resp =~ /Connection: close\r\n/);
                ok($resp !~ /0\r\n$/);
                if ($next) { process->nextTick($next) };
            }));
        });
    });
}

process->on('exit', sub {
    done_testing();
});

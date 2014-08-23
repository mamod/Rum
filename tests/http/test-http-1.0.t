use Rum;
use Test::More;
my $common = Require('../common');
my $assert = Require('assert');
my $net = Require('net');
my $http = Require('http');

my $body = "hello world\n";

my $common_port = $common->{PORT};

sub test {
    my ($handler, $request_generator, $response_validator) = @_;
    my $port = $common_port++;
    my $server = $http->createServer($handler);
    
    my $client_got_eof = 0;
    my $server_response = {
        data => '',
        chunks => []
    };
    
    my $cleanup = sub {
        $server->close();
        $response_validator->($server_response, $client_got_eof, 1);
    };
  
    my $timer = setTimeout($cleanup, 1000);
    process->on('exit', $cleanup);

    $server->listen($port);
    
    $server->on('listening', sub {
        my $c = $net->createConnection($port);
        
        $c->setEncoding('utf8');
        
        $c->on('connect', sub {
            $c->write($request_generator->());
        });
        
        $c->on('data', sub {
            my ($this, $chunk) = @_;
            $server_response->{data} .= $chunk;
            push @{$server_response->{chunks}}, $chunk;
        });
        
        $c->on('end', sub {
            $client_got_eof = 1;
            $c->end();
            $server->close();
            clearTimeout($timer);
            process->removeListener('exit', $cleanup);
            $response_validator->($server_response, $client_got_eof, 0);
        });
    });
}

{
    my $handler = sub {
        my ($this, $req, $res) = @_;
        is('1.0', $req->{httpVersion});
        is(1, $req->{httpVersionMajor});
        is(0, $req->{httpVersionMinor});
        $res->writeHead(200, {'Content-Type' => 'text/plain'});
        $res->end($body);
    };
    
    my $request_generator = sub {
        return "GET / HTTP/1.0\r\n\r\n";
    };
    
    my $response_validator = sub  {
        my ($server_response, $client_got_eof, $timed_out) = @_;
        my @m = split /\r\n\r\n/, $server_response->{data};
        is($m[1], $body);
        is(1, $client_got_eof);
        is(0, $timed_out);
    };
    
    test($handler, $request_generator, $response_validator);
};


#Don't send HTTP/1.1 status lines to HTTP/1.0 clients.
#
#https://github.com/joyent/node/issues/1234

{
    my $handler = sub {
        my ($this, $req, $res) = @_;
        is('1.0', $req->{httpVersion});
        is(1, $req->{httpVersionMajor});
        is(0, $req->{httpVersionMinor});
        $res->{sendDate} = 0;
        $res->writeHead(200, {'Content-Type' => 'text/plain'});
        $res->write('Hello, '); $res->_send('');
        $res->write('world!'); $res->_send('');
        $res->end();
    };
    
    my $request_generator = sub {
        return "GET / HTTP/1.0\r\n" .
          "User-Agent: curl/7.19.7 (x86_64-pc-linux-gnu) libcurl/7.19.7 " .
          "OpenSSL/0.9.8k zlib/1.2.3.3 libidn/1.15\r\n" .
          "Host: 127.0.0.1:1337\r\n" .
          "Accept: */*\r\n" .
          "\r\n";
    };
    
    my $response_validator = sub {
        my ($server_response, $client_got_eof, $timed_out) = @_;
        my $expected_response = "HTTP/1.1 200 OK\r\n" .
          "Content-Type: text/plain\r\n" .
          "Connection: close\r\n" .
          "\r\n" .
          "Hello, world!";
        
        is($expected_response, $server_response->{data});
        is(1, scalar @{$server_response->{chunks}});
        is(1, $client_got_eof);
        is(0, $timed_out);
    };
  
    test($handler, $request_generator, $response_validator);
};


{
    my $handler = sub {
        my ($this, $req, $res) = @_;
        is('1.1', $req->{httpVersion});
        is(1, $req->{httpVersionMajor});
        is(1, $req->{httpVersionMinor});
        $res->{sendDate} = 0;
        $res->writeHead(200, {'Content-Type' => 'text/plain'});
        $res->write('Hello, '); $res->_send('');
        $res->write('world!'); $res->_send('');
        $res->end();
    };
    
    my $request_generator = sub {
        return "GET / HTTP/1.1\r\n" .
          "User-Agent: curl/7.19.7 (x86_64-pc-linux-gnu) libcurl/7.19.7 " .
          "OpenSSL/0.9.8k zlib/1.2.3.3 libidn/1.15\r\n" .
          "Connection: close\r\n" .
          "Host: 127.0.0.1:1337\r\n" .
          "Accept: */*\r\n" .
          "\r\n";
    };
    
    my $response_validator = sub {
        my ($server_response, $client_got_eof, $timed_out) = @_;
        my $expected_response = "HTTP/1.1 200 OK\r\n" .
          "Content-Type: text/plain\r\n" .
          "Connection: close\r\n" .
          "Transfer-Encoding: chunked\r\n" .
          "\r\n" .
          "7\r\n" .
          "Hello, \r\n" .
          "6\r\n" .
          "world!\r\n" .
          "0\r\n" .
          "\r\n";
        
        is($expected_response, $server_response->{data});
        is(1, scalar @{$server_response->{chunks}});
        is(1, $client_got_eof);
        is(0, $timed_out);
    };
    
    test($handler, $request_generator, $response_validator);
};

process->on('exit', sub {
    done_testing();
});

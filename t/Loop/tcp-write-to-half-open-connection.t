use lib '../../lib';
use lib './lib';
use Test::More;

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;

my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;


my $tcp_server = {};
my $tcp_client = {};
my $tcp_peer = {}; #client socket as accept()-ed by server */
my $connect_req = {};
my $write_req = {};

my $write_cb_called = 0;
my $read_cb_called = 0;

sub connection_cb {
    my ($server, $status) = @_;

    ok($server == $tcp_server);
    ok($status == 0);
    
    $loop->tcp_init($tcp_peer);
    
    $loop->accept($server, $tcp_peer) or fail $!;
    
    $loop->read_start($tcp_peer, \&read_cb);
    my $buf = {};
    $buf->{base} = "hello\n";
    $buf->{len} = 6;
    $buf = $loop->buf_init("hello\n");
    $loop->write($write_req, $tcp_peer, $buf, 1, \&write_cb);
}


sub read_cb {
    my ($stream, $nread, $buf) = @_;
    if ($nread < 0) {
        printf("read_cb error: %s\n", $!+0);
        ok($! == ECONNRESET || $nread == $EOF);
        
        $loop->close($tcp_server);
        $loop->close($tcp_peer);
    }

    $read_cb_called++;
}


sub connect_cb {
    my ($req, $status) = @_;
    ok($req == $connect_req);
    ok($status == 0);

    #/* Close the client. */
    $loop->close($tcp_client);
}


sub write_cb {
    my ($req, $status) = @_;
    ok($status == 0);
    $write_cb_called++;
}


{

    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;
    
    $loop->tcp_init($tcp_server);
    
    $loop->tcp_bind($tcp_server, $addr, 0) or fail $!;

    $loop->listen($tcp_server, 1, \&connection_cb) or fail $!;

    $loop->tcp_init($tcp_client);

    $loop->tcp_connect($tcp_client,
                     $connect_req,
                     $addr,
                     \&connect_cb) or fail $!;

    $loop->run(RUN_DEFAULT);

    ok($write_cb_called > 0);
    ok($read_cb_called > 0);
    
}

done_testing();

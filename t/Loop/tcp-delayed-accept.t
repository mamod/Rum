use lib '../../lib';
use lib './lib';

use warnings;
use strict;
use Test::More;
use Rum::Loop;
use POSIX 'errno_h';
use Data::Dumper;

my $connection_cb_called = 0;
my $do_accept_called = 0;
my $close_cb_called = 0;
my $connect_cb_called = 0;

my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;

sub close_cb {
    my $handle = shift;
    ok($handle);
    $close_cb_called++;
}

sub do_accept {
    
    my ($timer_handle, $status) = @_;
    my $server = {};
    my $accepted_handle = {};
    my $r;
    
    ok($timer_handle);
    ok($status == 0);
    ok($accepted_handle);
    
    $loop->tcp_init($accepted_handle);
    
    $server = $timer_handle->{data};
    $loop->accept($server, $accepted_handle) or fail $!;
    
    $do_accept_called++;
    
    # Immediately close the accepted handle
    $loop->close($accepted_handle, \&close_cb);
    
    # After accepting the two clients close the server handle
    if ($do_accept_called == 2) {
        $loop->close($server, \&close_cb);
    }
    
    # Dispose the timer.
    $loop->close($timer_handle, \&close_cb);
}

sub connection_cb {
    my ($tcp, $status) = @_;
    my $r;
    my $timer_handle = {};
    ok($status == 0);
    
    # Accept the client after 1 second
    $loop->timer_init($timer_handle);
    
    $timer_handle->{data} = $tcp;
    
    $loop->timer_start($timer_handle, \&do_accept, 1000, 0);
    
    $connection_cb_called++;
}


sub start_server {
    my $server = {};
    my $r;

    my $addr = $loop->ip4_addr("0.0.0.0", $TEST_PORT);
    ok($addr);
    $loop->tcp_init($server);
    
    $r = $loop->tcp_bind($server, $addr);
    ok($r);
    
    $loop->listen($server, 128, \&connection_cb) or fail $!;
    
}

sub read_cb {
    my ($tcp, $nread, $buf) = @_;
    # The server will not send anything, it should close gracefully.
    if ($nread >= 0) {
        ok($nread == 0);
    } else {
        ok($tcp);
        ok($nread == $EOF);
        $loop->close($tcp, \&close_cb);
    }
}

sub connect_cb {
    my ($req, $status) = @_;
    my $r;
    ok($req);
    ok($status == 0);
    # Not that the server will send anything, but otherwise we'll never know
    # when the server closes the connection.
    $loop->read_start($req->{handle}, \&read_cb) or fail $!;
    $connect_cb_called++;
    undef $req;
}

sub client_connect {
    my $client = {};
    my $connect_req = {};
    my $r;
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT);
    ok($client);
    ok($connect_req);
    ok($addr);
    $r = $loop->tcp_init($client);
    
    $loop->tcp_connect($client, $connect_req,
                $addr,
                \&connect_cb) or fail $!;
}   

{
  start_server();
  client_connect();
  client_connect();
  
  $loop->run(RUN_DEFAULT);
  
  is($connection_cb_called, 2);
  is($do_accept_called, 2);
  is($connect_cb_called, 2);
  is($close_cb_called, 7);
}

done_testing();

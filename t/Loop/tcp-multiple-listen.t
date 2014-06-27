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

my $connection_cb_called = 0;
my $close_cb_called = 0;
my $connect_cb_called = 0;
my $server = {};
my $client = {};


sub close_cb {
    my $handle = shift;
    ok($handle);
    $close_cb_called++;
}


sub connection_cb {
    my ($tcp, $status) = @_;
    ok($status == 0);
    $loop->close($server, \&close_cb);
    $connection_cb_called++;
}


sub start_server {

  my $addr = $loop->ip4_addr("0.0.0.0", $TEST_PORT) or fail $!;

  $loop->tcp_init($server);

  $loop->tcp_bind($server, $addr, 0) or fail $!;

  $loop->listen($server, 128, \&connection_cb) or fail $!;

  $loop->listen($server, 128, \&connection_cb) or fail $!;
}


sub connect_cb {
    my ($req, $status) = @_;
    ok($req);
    ok($status == 0);
    undef($req);
    $loop->close($client, \&close_cb);
    $connect_cb_called++;
}


sub client_connect {

    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;
    my $connect_req = {};

    $loop->tcp_init($client);

    $loop->tcp_connect($client, $connect_req,
                    $addr,
                    \&connect_cb) or fail $!;
}



{
    start_server();
  
    client_connect();
  
    $loop->run(RUN_DEFAULT);
  
    ok($connection_cb_called == 1);
    ok($connect_cb_called == 1);
    ok($close_cb_called == 2);

}

done_testing();


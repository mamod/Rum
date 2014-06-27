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


my $check_handle = {};
my $timer_handle = {};
my $server_handle = {};
my $client_handle = {};
my $peer_handle = {};
my $write_req = {};
my $connect_req = {};

my $ticks = 0;


sub check_cb {
    $ticks++;
}


sub timer_cb {
    my ($handle, $status) = @_;
    $loop->close($check_handle);
    $loop->close($timer_handle);
    $loop->close($server_handle);
    $loop->close($client_handle);
    $loop->close($peer_handle);
}

#FIXME : this should not be called
sub read_cb {
  #ok(0, "read_cb should not have been called");
}

sub connect_cb {
    my ($req, $status) = @_;
    ok($req->{handle} == $client_handle);
    ok(0 == $status);
}

sub write_cb {
    my ($req, $status) = @_;
    ok($req->{handle} == $peer_handle);
    ok(0 == $status);
}

sub connection_cb {
    my ($handle, $status) = @_;
    
    my $buf = $loop->buf_init("PING", 4);
    
    ok(0 == $status);
    ok(1 == $loop->accept($handle, $peer_handle));
    $loop->read_start($peer_handle, \&read_cb);
    $loop->write($write_req, $peer_handle,
                       $buf, 1, \&write_cb);
}

{
    
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;
    
    $loop->timer_init($timer_handle);
    $loop->timer_start($timer_handle, \&timer_cb, 1000, 0);
    $loop->check_init($check_handle);
    $loop->check_start($check_handle, \&check_cb);
    $loop->tcp_init($server_handle);
    $loop->tcp_init($client_handle);
    $loop->tcp_init($peer_handle);
    $loop->tcp_bind($server_handle, $addr, 0) or fail $!;
    $loop->listen($server_handle, 1, \&connection_cb) or fail $!;
    $loop->tcp_connect($client_handle,
                       $connect_req,
                        $addr,
                        \&connect_cb) or fail $!;
    
    $loop->run(RUN_DEFAULT);
    
    #This is somewhat inexact but the idea is that the event loop should not
    #start busy looping when the server sends a message and the client isn't
    #reading.
    
    ok($ticks <= 20, "Number of ticks " . $ticks);
}

done_testing();

use lib '../../lib';
use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;
use Test::More;

my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;


my $tcp_handle = {};
my $connect_req = {};

my $write_cb_called = 0;
my $close_cb_called = 0;

my $NUM_WRITE_REQS = 32;

sub connect_cb {
    my ($conn_req, $status) = @_;
    
    my ($i,$r);
    my $req = {};
    my $buf = $loop->buf_init("PING", 4);
    
    for ($i = 0; $i < $NUM_WRITE_REQS; $i++) {
        $r = $loop->write($req, $tcp_handle, $buf, 1, \&write_cb) or die $!;
        ok($r == 1);
    }
    
    $loop->close($tcp_handle, \&close_cb);
}


sub write_cb {
    my ($req, $status) = @_;
    ##write callbacks should run before the close callback */
    ok($close_cb_called == 0);
    ok($req->{handle} == $tcp_handle);
    $write_cb_called++;
}


sub close_cb {
    my $handle = shift;
    ok($handle == $tcp_handle);
    $close_cb_called++;
}

sub connection_cb {
    my ($server, $status) = @_;
    ok($status == 0);
}

sub start_server {
    my ($loop, $handle) = @_;
    my $r;
    
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT);

    $loop->tcp_init($handle);
    
    $r = $loop->tcp_bind($handle, $addr, 0) or fail $!;
    ok($r == 1);
    
    $r = $loop->listen($handle, 128, \&connection_cb) or fail $!;
    ok($r == 1);
    $loop->unref($handle);
}


#Check that pending write requests have their callbacks
#invoked when the handle is closed.

{
    
    my $tcp_server = {};
    my $r;
    
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;
    
    # We can't use the echo server, it doesn't handle ECONNRESET.
    start_server($loop, $tcp_server);
    
    $r = $loop->tcp_init($tcp_handle);
    
    $r = $loop->tcp_connect($tcp_handle,
                    $connect_req,
                    $addr,
                    \&connect_cb) or fail $!;
    ok($r == 1);
    
    ok($write_cb_called == 0);
    ok($close_cb_called == 0);
    
    $loop->run(RUN_DEFAULT);
    
    printf STDERR ("%d of %d write reqs seen\n", $write_cb_called, $NUM_WRITE_REQS);
    
    ok($write_cb_called == $NUM_WRITE_REQS);
    ok($close_cb_called == 1);

}

done_testing();


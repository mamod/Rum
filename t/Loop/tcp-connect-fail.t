use lib '../../lib';
use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use POSIX 'errno_h';
use Data::Dumper;
use Test::More;

my $loop = Rum::Loop->new();
my $TEST_PORT = 9090;

my $tcp = {};
my $req = {};
my $connect_cb_calls = 0;
my $close_cb_calls = 0;

my $timer = {};
my $timer_close_cb_calls = 0;
my $timer_cb_calls = 0;

sub on_close {
    my ($handle) = @_;
    $close_cb_calls++;
}

sub timer_close_cb {
    my ($handle) = @_;
    $timer_close_cb_calls++;
}

sub timer_cb {
    my ($handle, $status) = @_;
    ok($status == 0);
    $timer_cb_calls++;

    #These are the important asserts. The connection callback has been made,
    #but libuv hasn't automatically closed the socket. The user must
    #uv_close the handle manually.

    ok($close_cb_calls == 0);
    ok($connect_cb_calls == 1);

    #Close the tcp handle.
    $loop->close($tcp, \&on_close);

    #Close the timer. */
    $loop->close($handle, \&timer_close_cb);
}

sub on_connect_with_close {
    my ($req, $status) = @_;
    
    ok($tcp == $req->{handle});
    
    is($status, ECONNREFUSED);
    $connect_cb_calls++;

    ok($close_cb_calls == 0);
    $loop->close($req->{handle}, \&on_close);
}

sub on_connect_without_close {
    my ($req, $status) = @_;
    is($status, ECONNREFUSED);
    $connect_cb_calls++;

    $loop->timer_start($timer, \&timer_cb, 100, 0);

    ok($close_cb_calls == 0);
}

sub connection_fail {
    my ($connect_cb) = @_;
    my $client_addr;
    my $server_addr;
    
    $client_addr = $loop->ip4_addr("0.0.0.0", 0) or fail $!;

    #There should be no servers listening on this port. */
    $server_addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;

    #Try to connect to the server and do NUM_PINGS ping-pongs. */
    $loop->tcp_init($tcp);

    #We are never doing multiple reads/connects at a time anyway.
    #so these handles can be pre-initialized.
    ok( $loop->tcp_bind($tcp, $client_addr) );

    $loop->tcp_connect($tcp, $req,
                     $server_addr,
                     $connect_cb) or fail $!;
    
    $loop->run(RUN_DEFAULT);

    ok($connect_cb_calls == 1);
    ok($close_cb_calls == 1);
}


# This test attempts to connect to a port where no server is running. We
# expect an error.
{
    connection_fail(\&on_connect_with_close);
    ok($timer_close_cb_calls == 0);
    ok($timer_cb_calls == 0);
}


# This test is the same as the first except it check that the close
# callback of the tcp handle hasn't been made after the failed connection
# attempt.

{
    my $r;
    $connect_cb_calls = 0;
    $close_cb_calls = 0;
    $loop->timer_init($timer);

    connection_fail(\&on_connect_without_close);

    ok($timer_close_cb_calls == 1);
    ok($timer_cb_calls == 1);
}

done_testing(18);

1;

use lib '../../lib';
use lib './lib';
use Test::More;

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;
use Rum::Loop::Flags '$ECANCELED';
my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;

my $timer1_handle = {};
my $timer2_handle = {};
my $tcp_handle = {};

my $connect_cb_called = 0;
my $timer1_cb_called = 0;
my $close_cb_called = 0;

sub close_cb {
    $close_cb_called++;
}

sub connect_cb {
    my ($req, $status) = @_;
    #is($status, $ECANCELED);
    ok($status);
    diag($status);
    $loop->timer_stop($timer2_handle);
    $connect_cb_called++;
}

sub timer1_cb {
    my ($handle, $status) = @_;
    $loop->close($handle, \&close_cb);
    $loop->close($tcp_handle, \&close_cb);
    $timer1_cb_called++;
}

sub timer2_cb {
    fail("should not be called");
}

{
    my $connect_req = {};
    ##FIXME
    ##set tcp_connect to nonblocking mode
    ##then change ip address to some invalid compinations 1.2.3.4 
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;
    $loop->tcp_init($tcp_handle);
    $loop->tcp_connect($tcp_handle,
                       $connect_req,
                       $addr,
                        \&connect_cb) or fail $!;
    
    $loop->timer_init($timer1_handle);
    $loop->timer_start($timer1_handle, \&timer1_cb, 50, 0);
    $loop->timer_init($timer2_handle);
    $loop->timer_start($timer2_handle, \&timer2_cb, 86400 * 1000, 0);
    $loop->run(RUN_DEFAULT);

    ok($connect_cb_called == 1);
    ok($timer1_cb_called == 1);
    ok($close_cb_called == 2);   
}

done_testing();

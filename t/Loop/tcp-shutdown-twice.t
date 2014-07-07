use lib './lib';

use warnings;
use strict;
use Rum::Loop;

use POSIX 'errno_h';
use Data::Dumper;

my $loop = Rum::Loop->new();

use Test::More;

use FindBin '$Bin';
require "$Bin/helper.pl";
helper_fork_echo_server();

*assert = *ok;

my $TEST_PORT = 9090;
my $EOF = -4095;

my $req1 = {};
my $req2 = {};

my $shutdown_cb_called = 0;
sub close_cb {}

sub shutdown_cb {
    my ($req, $status) = @_;
    assert($req == $req1);
    assert($status == 0, "status " . $status);
    $shutdown_cb_called++;
    $loop->close($req->{handle}, \&close_cb);
}

sub connect_cb {
    my ($req, $status) = @_;
    
    assert($status == 0, "status " . $status);
    
    $loop->shutdown($req1, $req->{handle}, \&shutdown_cb) or fail $!;
    my $r = $loop->shutdown($req2, $req->{handle}, \&shutdown_cb);
    assert(!$r);
}

#TEST_IMPL(shutdown_twice)
{
    my $h = {};
    
    my $connect_req = {};

    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT);
    
    $loop->tcp_init($h);
    
    $loop->tcp_connect(
                     $h,
                     $connect_req,
                     $addr,
                     \&connect_cb) or fail $!;
    
    $loop->run(RUN_DEFAULT);

    assert($shutdown_cb_called == 1);
    helper_kill_echo_server();
    done_testing();
}

1;

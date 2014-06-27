use lib '../../lib';
use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags qw[:Errors :Platform];
use POSIX 'errno_h';
use Data::Dumper;
use Test::More;
#use Rum::Loop::Utils 'assert';
*assert = \&ok;

my $connect_cb_called = 0;
my $close_cb_called = 0;

my $connect_req = {};
my $timer = {};
my $conn = {};

my $loop = Rum::Loop::default_loop();

sub connect_cb {
    my ($req, $status) = @_;
    assert($req == $connect_req);
    my $error = "$!" . '';
    ok($status, $error);
    assert($status == $!)  if $isWin;
    assert($status == $ECANCELED, $!) if !$isWin;
    $connect_cb_called++;
}

sub timer_cb {
    my ($handle, $status) = @_;
    assert($handle == $timer);
    $loop->close($conn, \&close_cb);
    $loop->close($timer, \&close_cb);
}

sub close_cb {
    my $handle = shift;
    assert($handle == $conn || $handle == $timer);
    $close_cb_called++;
}

{
    
    my $addr = $loop->ip4_addr("8.8.8.8", 9999) or die $!;
    
    my $r = $loop->timer_init($timer);
    
    $loop->timer_start($timer, \&timer_cb, 50, 0);
    
    $loop->tcp_init($conn);
    
    $loop->tcp_connect($conn,
                       $connect_req,
                       $addr,
                       \&connect_cb) or die $!+0;
    
    $loop->run(RUN_DEFAULT);
    
}

done_testing();

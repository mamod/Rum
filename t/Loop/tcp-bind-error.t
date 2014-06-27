use lib './lib';
use Rum::Loop;
use Test::More;
use strict;
use POSIX 'errno_h';

my $close_cb_called = 0;
my $TEST_PORT = 9090;
my $TEST_PORT_2 = 9094;

my $loop = Rum::Loop->new();

my $isWin = $^O eq 'MSWin32';

sub close_cb {
    my $handle = shift;
    ok($handle);
    $close_cb_called++;
}

{
    my $addr;
    my $server1 = {};
    my $server2 = {};
    my $r;
  
    $addr = $loop->ip4_addr("0.0.0.0", $TEST_PORT);
    $r = $loop->tcp_init($server1);
    ok($r == 0);
    $loop->tcp_bind($server1, $addr) or fail($!);
    
    $loop->tcp_init($server2);
    
    $r = $loop->tcp_bind($server2, $addr)  or fail($!);
    
    $loop->listen($server1, 128) or fail($!);
    
    $r = $loop->listen($server2, 128);
    
    ##FIXME windows seems to allow listining on same address?
    ok(!$r && $! == EADDRINUSE) if !$isWin;
    
    $loop->close($server1, \&close_cb);
    $loop->close($server2, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    is($close_cb_called, 2);
}

{
    my $addr;
    my $server = {};
    my $r;
    $close_cb_called = 0;
    
    $addr = $loop->ip4_addr("127.255.255.255", $TEST_PORT) or fail('should not fail');
    
    $loop->tcp_init($server);
    
    #It seems that Linux is broken here - bind succeeds.
    $r = $loop->tcp_bind($server, $addr);
    ok($! == EADDRNOTAVAIL || $r == 1);
    
    $loop->close($server, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    ok($close_cb_called == 1);
}

{
    $close_cb_called = 0;
    my $addr;
    my $server = {};
    my $r;
    $addr = $loop->ip4_addr("4.4.4.4", $TEST_PORT);
    $r = $loop->tcp_init($server);
    $r = $loop->tcp_bind($server, $addr);
    ok($! == EADDRNOTAVAIL);
    $loop->close($server, \&close_cb);
    $loop->run(RUN_DEFAULT);
    ok($close_cb_called == 1);
}

#TEST_IMPL(tcp_bind_error_fault)
{
    $close_cb_called = 0;
    my $garbage_addr = "blah blah blah blah blah blah blah blah blah blah blah blah";
    my $server = {};
    my $r;
    
    $loop->tcp_init($server);
    $r = $loop->tcp_bind($server, $garbage_addr);
    
    #this behaves different than libuv
    #which gives EINVAL
    ok(!$r);
    ok($! == EINVAL, $!.'');
    #ok($! == EAFNOSUPPORT || $! == EADDRNOTAVAIL, $!+'');
    
    $loop->close($server, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    ok($close_cb_called == 1);
}


{
    my $addr1;
    my $addr2;
    my $server = {};
    my $r;
    $close_cb_called = 0;
    
    $addr1 = $loop->ip4_addr("0.0.0.0", $TEST_PORT);
    $addr2 = $loop->ip4_addr("0.0.0.0", $TEST_PORT_2);
    
    $loop->tcp_init($server);
    
    $loop->tcp_bind($server, $addr1) or fail $!;
    
    $r = $loop->tcp_bind($server, $addr2);
    ok(!$r);
    #on windows returns WSAEINVAL = 10022
    ok($! == EINVAL || $! == 10022);
    
    $loop->close($server, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    ok($close_cb_called == 1);
    
}

{
    my $addr;
    my $server = {};
    my $r;
    
    $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT);
    
    $loop->tcp_init($server);
    $loop->tcp_bind($server, $addr) or fail $!;
}


{
    my $r;
    my $server = {};
    $loop->tcp_init($server);
    
    $r = $loop->listen($server, 128);
    #FIXME windows croak without binding an address
    #before listening with WSAEINVAL (10022)
    ok($r) if !$isWin;
}

done_testing();

1;

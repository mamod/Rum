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

my $server = {};
my $client = {};
my $incoming = {};
my $connect_cb_called = 0;
my $close_cb_called = 0;
my $connection_cb_called = 0;
my $bytes_read = 0;
my $bytes_written = 0;


sub close_cb {
    $close_cb_called++;
}


sub connect_cb {
    my ($req,$status) = @_;
    my $zeroes = '0' x 1024;
    ok($status == 0);
    $connect_cb_called++;
    my $zlength = length $zeroes;
    
    for (;;) {
        my $buf = [$zeroes];
        #my $buf = $loop->buf_init($zeroes);
        my $r = $loop->try_write($client, $buf, 1);
        ok($r >= 0);
        $bytes_written += $r;
        print Dumper $bytes_written;
        #Partial write
        if ($r != $zlength) {
            last;
        }
    }
    
    $loop->close($client, \&close_cb);
}


sub read_cb {
    my ($tcp, $nread, $buf) = @_;
    if ($nread < 0) {
        
        $loop->close($tcp, \&close_cb);
        $loop->close($server, \&close_cb);
        return;
    }

    $bytes_read += $nread;
}


sub connection_cb {
    my ($tcp, $status) = @_;
    ok($status == 0);
    
    $loop->tcp_init($incoming);
    $loop->accept($tcp, $incoming) or die $!;
    
    $connection_cb_called++;
    $loop->read_start($incoming, \&read_cb);
}

sub start_server {
    
    my $addr = $loop->ip4_addr("0.0.0.0", $TEST_PORT) or die $!;
    
    $loop->tcp_init($server);
    $loop->tcp_bind($server, $addr, 0) or die $!;
    $loop->listen($server, 128, \&connection_cb) or die $!;
}


{
    my $connect_req = {};
    
    start_server();
    
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or die $!;
    
    $loop->tcp_init($client);
    $loop->tcp_connect($client,
                        $connect_req,
                        $addr,
                        \&connect_cb) or die $!;
    
    $loop->run(RUN_DEFAULT);
    
    ok($connect_cb_called == 1);
    ok($close_cb_called == 3);
    ok($connection_cb_called == 1);
    ok($bytes_read == $bytes_written);
    
    ok($bytes_written > 0);
    
}

done_testing();

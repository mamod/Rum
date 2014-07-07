use lib './lib';
use Test::More;

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;
use FindBin '$Bin';

require "$Bin/helper.pl";
helper_fork_echo_server();

my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;

my $WRITES = 3;
my $CHUNKS_PER_WRITE = 4096;
my $CHUNK_SIZE = 1024 * 10;

my $TOTAL_BYTES = $WRITES * $CHUNKS_PER_WRITE * $CHUNK_SIZE;

my $send_buffer = '';

my $shutdown_cb_called = 0;
my $connect_cb_called = 0;
my $write_cb_called = 0;
my $close_cb_called = 0;
my $bytes_sent = 0;
my $bytes_sent_done = 0;
my $bytes_received_done = 0;

my $connect_req = {};
my $shutdown_req = {};
my $write_reqs = [{},{},{}];



sub close_cb {
    my ($handle) = @_;
    assert($handle);
    $close_cb_called++;
}

sub shutdown_cb {
    my ($req, $status) = @_;
    
    assert($req == $shutdown_req);
    assert($status == 0);

    my $tcp = $req->{handle};
    
    #The write buffer should be empty by now.
    assert($tcp->{write_queue_size} == 0);
    
    #Now we wait for the EOF
    $shutdown_cb_called++;
    
    #We should have had all the writes called already.
    assert($write_cb_called == $WRITES);
}

my $t = 0;
sub read_cb {
    my ($tcp, $nread, $buf) = @_;
    assert($tcp);
    
    if ($nread >= 0) {
        $bytes_received_done += $nread;
        #print $bytes_received_done . "\n";
    } else {
        assert($nread == $EOF, $!);
        diag("GOT EOF\n");
        $loop->close($tcp, \&close_cb);
    }
    
    undef $buf->{base};
}

sub write_cb {
    my ($req, $status) = @_;
    
    assert($req);
    
    if ($status) {
        printf("uv_write error: %s\n", $!);
        assert(0);
    }

    $bytes_sent_done += $CHUNKS_PER_WRITE * $CHUNK_SIZE;
    $write_cb_called++;
}

sub connect_cb {
    my ($req, $status) = @_;
    
    my ( $i, $j, $r);
    
    assert($req == $connect_req);
    assert($status == 0, $!);
    
    my $stream = $req->{handle};
    $connect_cb_called++;
    my $send_bufs = [];
    
    #Write a lot of data
    for ($i = 0; $i < $WRITES; $i++) {
        my $write_req = $write_reqs->[$i];
        for ($j = 0; $j < $CHUNKS_PER_WRITE; $j++) {
            $send_bufs->[$j] = $send_buffer;
            $bytes_sent += $CHUNK_SIZE;
        }
        
        $loop->write($write_req, $stream, $send_bufs, $CHUNKS_PER_WRITE, \&write_cb) or die $!;
    }
    
    #Shutdown on drain.
    $loop->shutdown($shutdown_req, $stream, \&shutdown_cb) or die $!;
    
    #Start reading
    $loop->read_start($stream, \&read_cb) or die $!;
}


{
    my $client = {};
    
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or die $!;
    $send_buffer = '0' x $CHUNK_SIZE;
    $loop->tcp_init($client);

    $loop->tcp_connect($client, $connect_req,
                     $addr,
                     \&connect_cb) or die $!;
    
    
    $loop->run(RUN_DEFAULT);
    
    ok($shutdown_cb_called == 1);
    ok($connect_cb_called == 1);
    ok($write_cb_called == $WRITES);
    ok($close_cb_called == 1);
    ok($bytes_sent == $TOTAL_BYTES);
    ok($bytes_sent_done == $TOTAL_BYTES);
    ok($bytes_received_done == $TOTAL_BYTES, $bytes_received_done . ' == ' . $TOTAL_BYTES);
    done_testing();
    undef $send_buffer;
    helper_kill_echo_server();
}

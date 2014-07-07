use lib './lib';

use warnings;
use strict;
use Rum::Loop;

use POSIX 'errno_h';
use Data::Dumper;
use Test::More;

use FindBin '$Bin';
require "$Bin/helper.pl";
helper_fork_echo_server();

*assert = *ok;

my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;

my $timer = {};
my $tcp = {};
my $connect_req = {};
my $write_req = {};
my $shutdown_req = {};
my $qbuf = {};
my $got_q = 0;
my $got_eof = 0;
my $called_connect_cb = 0;
my $called_shutdown_cb = 0;
my $called_tcp_close_cb = 0;
my $called_timer_close_cb = 0;
my $called_timer_cb = 0;




sub read_cb {
    my ($t, $nread, $buf) = @_;
    assert($t == $tcp);
    
    if ($nread == 0) {
        undef $buf->{base};
        return;
    }
    
    if (!$got_q) {
        assert($nread == 1);
        assert(!$got_eof);
        assert($buf->{base} eq 'Q');
        undef $buf->{base};
        $got_q = 1;
        print("got Q\n");
    } else {
        assert($nread == $EOF);
        if ($buf->{base}) {
            undef $buf->{base};
        }
        $got_eof = 1;
        print("got EOF\n");
    }
}


sub shutdown_cb {
    my ($req,$status) = @_;
    assert($req == $shutdown_req);
    
    assert($called_connect_cb == 1);
    assert(!$got_eof);
    assert($called_tcp_close_cb == 0);
    assert($called_timer_close_cb == 0);
    assert($called_timer_cb == 0);
    
    $called_shutdown_cb++;
}

sub connect_cb {
    my ($req,$status) = @_;
    assert($status == 0);
    assert($req == $connect_req);
    
    #Start reading from our connection so we can receive the EOF. */
    $loop->read_start($tcp, \&read_cb);
    
    #Write the letter 'Q' to gracefully kill the echo-server. This will not
    #effect our connection.
    
    $loop->write($write_req, $tcp, $qbuf, 1, undef);
    
    #Shutdown our end of the connection. */
    $loop->shutdown($shutdown_req, $tcp, \&shutdown_cb) or die $!;

    $called_connect_cb++;
    assert($called_shutdown_cb == 0);
}

sub tcp_close_cb {
    my $handle = shift;
    assert($handle == $tcp);
    
    assert($called_connect_cb == 1);
    assert($got_q);
    assert($got_eof);
    assert($called_timer_cb == 1);
    
    $called_tcp_close_cb++;
}

sub timer_close_cb {
    my $handle = shift;
    assert($handle == $timer);
    $called_timer_close_cb++;
}

sub timer_cb {
    my $handle = shift;
    assert($handle == $timer);
    $loop->close($handle, \&timer_close_cb);

    #The most important assert of the test: we have not received
    #tcp_close_cb yet.
    
    assert($called_tcp_close_cb == 0);
    $loop->close($tcp, \&tcp_close_cb);
    $called_timer_cb++;
}

#This test has a client which connects to the echo_server and immediately
#issues a shutdown. The echo-server, in response, will also shutdown their
#connection. We check, with a timer, that libuv is not automatically
#calling uv_close when the client receives the EOF from echo-server.

{
    $qbuf = $loop->buf_init('Q');
    $loop->timer_init($timer);
    
    $loop->timer_start($timer, \&timer_cb, 100, 0);
    
    my $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or die $!;
    $loop->tcp_init($tcp);

    $loop->tcp_connect($tcp,
                    $connect_req,
                    $addr,
                    \&connect_cb) or die $!;
    
    $loop->run(RUN_DEFAULT);
    
    assert($called_connect_cb == 1);
    assert($called_shutdown_cb == 1);
    assert($got_eof);
    assert($got_q);
    assert($called_tcp_close_cb == 1);
    assert($called_timer_close_cb == 1);
    assert($called_timer_cb == 1);
    done_testing();
    
}

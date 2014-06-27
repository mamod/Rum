##this is a Rum::Loop echo server

use lib '../../lib';
use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags ':Errors';
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;

my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;

my $server_closed = 0;
my $serverType;

my $tcpServer = {};
my $udpServer = {};
my $pipeServer = {};
my $server = {};

my $write = {
    buf => {},
    req => {}
};

sub after_write {
    my ($req, $status) = @_;
    my $wr = $write;
    undef $wr->{buf};
    undef $wr->{req};
    
    if ($status == 0){
        return;
    }

    printf("uv_write error: %s\n", $status);

    if ($status == $ECANCELED){
        return;
    }

    assert($status == EPIPE);
    $loop->close($req->{handle}, \&on_close);
}

sub after_shutdown {
    my ($req, $status) = @_;
    $loop->close($req->{handle}, \&on_close);
    undef $req;
}

sub after_read {
    my ($handle,$nread,$buf) = @_;
    my $req = {};
    
    if ($nread < 0) {
        #Error or EOF
        assert($nread == $EOF, $!);
        
        if ($buf->{base}) {
            undef $buf->{base};
        }
        
        $loop->shutdown($req, $handle, \&after_shutdown);
        
        return;
    }
    
    if ($nread == 0) {
        #Everything OK, but nothing read.
        undef $buf->{base};
        return;
    }

    my $wr = $write;
    #$wr->{buf} = $loop->buf_init($buf->{base}, $nread);
    $wr->{buf} = [$buf->{base}];
    $wr->{req} = {};
    $loop->write( $wr->{req}, $handle,  $wr->{buf}, 1, \&after_write) or die $!;
}


sub on_close {
    my $peer = shift;
    undef $peer;
}

sub on_connection {
    my ($server, $status) = @_;
    my $stream = {};
    
    assert($server == $tcpServer);
    
    if ($status != 0) {
        fprintf("Connect error %s\n", $status);
    }
    
    assert($status == 0);
    
    if ($serverType eq 'TCP'){
        $loop->tcp_init($stream);
    } else {
        die "wrong type";
    }

    # associate server with stream
    #$stream->{data} = $server;
    
    $loop->accept($server, $stream) or die $!;

    $loop->read_start($stream, \&after_read);
}


sub on_server_close {
    my $handle = shift;
    assert($handle == $server);
}

sub tcp4_echo_start {
    my $port = shift;

    my $addr = $loop->ip4_addr("0.0.0.0", $port);

    $server = $tcpServer;
    $serverType = 'TCP';

    $loop->tcp_init($tcpServer);

    $loop->tcp_bind($tcpServer, $addr, 0) or die $!;

    $loop->listen($tcpServer, 128, \&on_connection) or die $!;
}


{
  tcp4_echo_start($TEST_PORT);
  $loop->run(RUN_DEFAULT);
}

1;

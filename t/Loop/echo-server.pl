use lib './lib';
use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags ':Errors';
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;

##should run
# 1 - tcp-writealot.pl
# 2 - tcp-shutdown-eof.pl
# 3-  tcp-shutdown-close.pl


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
    
    
    if ($nread == 1) {
        if ($buf->{base} eq 'Q') {
            $loop->close($server, \&on_server_close);
            $server_closed = 1;
        }
    }
    
    
    ##Scan for the letter Q which signals that we should quit the server.
    ##If we get QS it means close the stream.
    #my @buf = split //, $buf->{base};
    #
    #if (!$server_closed) {
    #    for (my $i = 0; $i < $nread; $i++) {
    #        if ($buf[$i] eq 'Q') {
    #            if ($i + 1 < $nread && $buf[$i + 1] eq 'S') {
    #                undef $buf->{base};
    #                $loop->close($handle, \&on_close);
    #                return;
    #            } else {
    #                $loop->close($server, \&on_server_close);
    #                $server_closed = 1;
    #            }
    #        }
    #    }
    #}
    
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


#static void on_send(uv_udp_send_t* req, int status);
#
#
#static void on_recv(uv_udp_t* handle,
#                    ssize_t nread,
#                    const uv_buf_t* rcvbuf,
#                    const struct sockaddr* addr,
#                    unsigned flags) {
#  uv_udp_send_t* req;
#  uv_buf_t sndbuf;
#
#  ASSERT(nread > 0);
#  ASSERT(addr->sa_family == AF_INET);
#
#  req = malloc(sizeof(*req));
#  ASSERT(req != NULL);
#
#  sndbuf = *rcvbuf;
#  ASSERT(0 == uv_udp_send(req, handle, &sndbuf, 1, addr, on_send));
#}
#
#
#static void on_send(uv_udp_send_t* req, int status) {
#  ASSERT(status == 0);
#  free(req);
#}


sub tcp4_echo_start {
    my $port = shift;

    my $addr = $loop->ip4_addr("0.0.0.0", $port);

    $server = $tcpServer;
    $serverType = 'TCP';

    $loop->tcp_init($tcpServer);

    $loop->tcp_bind($tcpServer, $addr, 0) or die $!;

    $loop->listen($tcpServer, 128, \&on_connection) or die $!;
}


#static int tcp6_echo_start(int port) {
#  struct sockaddr_in6 addr6;
#  int r;
#
#  ASSERT(0 == uv_ip6_addr("::1", port, &addr6));
#
#  server = (uv_handle_t*)&tcpServer;
#  serverType = TCP;
#
#  r = uv_tcp_init(loop, &tcpServer);
#  if (r) {
#    /* TODO: Error codes */
#    fprintf(stderr, "Socket creation error\n");
#    return 1;
#  }
#
#  /* IPv6 is optional as not all platforms support it */
#  r = uv_tcp_bind(&tcpServer, (const struct sockaddr*) &addr6, 0);
#  if (r) {
#    /* show message but return OK */
#    fprintf(stderr, "IPv6 not supported\n");
#    return 0;
#  }
#
#  r = uv_listen((uv_stream_t*)&tcpServer, SOMAXCONN, on_connection);
#  if (r) {
#    /* TODO: Error codes */
#    fprintf(stderr, "Listen error\n");
#    return 1;
#  }
#
#  return 0;
#}
#
#
#static int udp4_echo_start(int port) {
#  int r;
#
#  server = (uv_handle_t*)&udpServer;
#  serverType = UDP;
#
#  r = uv_udp_init(loop, &udpServer);
#  if (r) {
#    fprintf(stderr, "uv_udp_init: %s\n", uv_strerror(r));
#    return 1;
#  }
#
#  r = uv_udp_recv_start(&udpServer, echo_alloc, on_recv);
#  if (r) {
#    fprintf(stderr, "uv_udp_recv_start: %s\n", uv_strerror(r));
#    return 1;
#  }
#
#  return 0;
#}
#
#
#static int pipe_echo_start(char* pipeName) {
#  int r;
#
##ifndef _WIN32
#  {
#    uv_fs_t req;
#    uv_fs_unlink(uv_default_loop(), &req, pipeName, NULL);
#    uv_fs_req_cleanup(&req);
#  }
##endif
#
#  server = (uv_handle_t*)&pipeServer;
#  serverType = PIPE;
#
#  r = uv_pipe_init(loop, &pipeServer, 0);
#  if (r) {
#    fprintf(stderr, "uv_pipe_init: %s\n", uv_strerror(r));
#    return 1;
#  }
#
#  r = uv_pipe_bind(&pipeServer, pipeName);
#  if (r) {
#    fprintf(stderr, "uv_pipe_bind: %s\n", uv_strerror(r));
#    return 1;
#  }
#
#  r = uv_listen((uv_stream_t*)&pipeServer, SOMAXCONN, on_connection);
#  if (r) {
#    fprintf(stderr, "uv_pipe_listen: %s\n", uv_strerror(r));
#    return 1;
#  }
#
#  return 0;
#}


{
  tcp4_echo_start($TEST_PORT);
  $loop->run(RUN_DEFAULT);
}


#HELPER_IMPL(tcp6_echo_server) {
#  loop = uv_default_loop();
#
#  if (tcp6_echo_start(TEST_PORT))
#    return 1;
#
#  uv_run(loop, UV_RUN_DEFAULT);
#  return 0;
#}
#
#
#HELPER_IMPL(pipe_echo_server) {
#  loop = uv_default_loop();
#
#  if (pipe_echo_start(TEST_PIPENAME))
#    return 1;
#
#  uv_run(loop, UV_RUN_DEFAULT);
#  return 0;
#}
#
#
#HELPER_IMPL(udp4_echo_server) {
#  loop = uv_default_loop();
#
#  if (udp4_echo_start(TEST_PORT))
#    return 1;
#
#  uv_run(loop, UV_RUN_DEFAULT);
#  return 0;
#}

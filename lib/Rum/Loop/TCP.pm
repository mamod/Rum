package Rum::Loop::TCP;
use strict;
use warnings;
use Socket;
use Rum::Loop::Stream ();
use Rum::Loop::Queue;
use Data::Dumper;
use POSIX qw(:errno_h);
use Rum::Loop::Flags qw(:Stream :IO :Errors :Platform $CLOSING $CLOSED $KQUEUE);
use Rum::Loop::Utils 'assert';

my $REUSE = $isWin ? 0 : 1;
my $SOCK_NONBLOCK = $NONBLOCK;
my $SOCK_CLOEXEC = $CLOEXEC;
my $SO_NOSIGPIPE = eval "SO_NOSIGPIPE" || 0;

use base qw/Exporter/;
our @EXPORT = qw (
    ip4_addr
    ip6_addr
    tcp_init
    tcp_close
    tcp_bind
    tcp_connect
    tcp_listen
    tcp_open
    tcp_getsockname
    tcp_getpeername
    tcp_keepalive
    listen
);

sub tcp_init {
    my ($loop,$tcp) = @_;
    $loop->handle_init($_[1],'TCP');
    $tcp->{accepted_fh} = 0;
    $tcp->{accepted_fd} = -1;
    $loop->stream_init($_[1],'TCP');
    return 0;
}

sub ip4_addr {
    my ($loop, $ip, $port) = @_;
    
    my $ip_address = inet_aton($ip);
    if (!$ip_address) {
        return;
    }
    
    my $address = sockaddr_in($port, $ip_address) or return;
    return $address;
}

sub tcp_bind {
    my ($loop, $tcp, $addr) = @_;
    $! = 0;
    my $family = sockaddr_family $addr or return;
    if ($family != AF_INET) {
        $! = EINVAL;
        return;
    }
    
    _maybe_new_socket($tcp, $family, $STREAM_READABLE | $STREAM_WRITABLE)
        or return;
    
    if (!setsockopt($tcp->{io_watcher}->{fh}, SOL_SOCKET, SO_REUSEADDR,
                    pack("l", $REUSE))){
        return;
    }
    
    $! = 0;
    if (!bind($tcp->{io_watcher}->{fh}, $addr) && $! != EADDRINUSE ){
        return;
    }
    
    $tcp->{delayed_error} = $!;
    return 1;
}

sub _maybe_new_socket {
    my ($tcp,$domain,$flags) = @_;
    
    if ($tcp->{io_watcher}->{fh}) {
        return 1;
    }
    
    my $sockfh = _socket(AF_INET, SOCK_STREAM, 0);
    if (!$sockfh) {
        return;
    }
    
    if (!Rum::Loop::Stream::stream_open($tcp, $sockfh, $flags)){
        _close($sockfh);
        return;
    }
    
    return 1;
}


sub _socket {
    my ($domain, $type, $protocol) = @_;
    my $sockfh;
    $! = 0;
    
    #FIXME
    #if ($SOCK_NONBLOCK && $SOCK_CLOEXEC ) {
    #    my $t = socket($sockfh, $domain, $type | $SOCK_NONBLOCK | $SOCK_CLOEXEC,
    #           $protocol);
    #    
    #    if (!$t && $! != EINVAL) {
    #        return;
    #    }
    #    
    #    return $sockfh if (fileno $sockfh);
    #}
    
    my $saved_errno = $!;
    socket($sockfh, $domain, $type, $protocol) or return;
    $! = $saved_errno;
    my $ret = Rum::Loop::Core::nonblock($sockfh,1);
    if ($ret) {
        $ret = Rum::Loop::Core::cloexec($sockfh,1);
    }
    
    if (!$ret) {
        return;
    }
    
    ##solaris / bsd
    if ($SO_NOSIGPIPE) {
        setsockopt($sockfh, SOL_SOCKET, $SO_NOSIGPIPE, pack(1,1)) or return;
    }
    
    return $sockfh;
}

sub tcp_open {
    my ($loop, $handle, $sock) = @_;
    return Rum::Loop::Stream::stream_open($handle,
                         $sock,
                         $STREAM_READABLE | $STREAM_WRITABLE);
}

sub listen {
    my ($loop, $tcp, $backlog, $cb) = @_;
    my $ret = EINVAL;
    
    if ($tcp->{type} eq 'TCP') {
        $ret = $loop->tcp_listen($tcp,$backlog,$cb);
    } elsif ($tcp->{type} eq 'NAMED_PIPE'){
        $ret = $loop->pipe_listen($tcp, $backlog, $cb);
    }
    
    if (!$ret) {
        return;
    }
    
    $loop->handle_start($tcp);
    return $ret;
}

sub tcp_listen {
    my ($loop, $tcp, $backlog, $cb) = @_;
    my $single_accept = -1;
    if ($tcp->{delayed_error}) {
        $! = $tcp->{delayed_error};
        return;
    }
    
    if (!_maybe_new_socket($tcp, AF_INET, $STREAM_READABLE)) {
        return;
    }
    
    $! = 0;
    CORE::listen( $tcp->{io_watcher}->{fh}, $backlog ) or return;
    
    $tcp->{connection_cb} = $cb;
    $tcp->{io_watcher}->{cb} = \&Rum::Loop::Stream::server_io;
    $loop->io_start($tcp->{io_watcher}, $POLLACCEPT);
    
    return 1;
}

sub _close {
    close $_[0];
    $_[0] = 0;
}

sub tcp_connect {
    my ($loop, $handle, $req, $addr, $cb) = @_;
    my ($err,$r);
    
    my $family = sockaddr_family $addr or return;
    if ($family != AF_INET) {
        $! = EINVAL;
        return;
    }
    
    assert($handle->{type} eq 'TCP');
    
    if ($handle->{connect_req}) {
        $! = EALREADY; #FIXME(bnoordhuis) -EINVAL or maybe -EBUSY.
        return;
    }
    
    _maybe_new_socket($handle, $family,
                $STREAM_READABLE | $STREAM_WRITABLE) or return;
    
    $handle->{delayed_error} = 0;
    my $fh = Rum::Loop::Stream::stream_fh($handle);
    
    do {
        $r = CORE::connect($fh, $addr);
        my $wait = '';
        if ($isWin) {
            vec($wait, fileno $fh, 1) = 1;
            select $wait,$wait,$wait,0.001;
        }
    } while (!$r && ($! == EINTR || ($isWin && $! == EWOULDBLOCK)) );
    
    if (!$r) {
        if ($! == EINPROGRESS || ($isWin && ($! == EISCONN || $! == 10022 )) ) {
            
        } elsif ( $! == ECONNREFUSED || ($isWin && $! == EALREADY) ) {
            $handle->{delayed_error} = ECONNREFUSED;
        } else {
            return;
        }
    }
    
    $loop->req_init($req, 'CONNECT');
    $req->{cb} = $cb;
    $req->{handle} = $handle;
    $req->{queue} = QUEUE_INIT($req);
    $handle->{connect_req} = $req;
    
    $loop->io_start($handle->{io_watcher}, $POLLOUT);
    
    if ($handle->{delayed_error}) {
        $loop->io_feed($handle->{io_watcher});
    }
    
    return 1;
}

sub tcp_close {
    my $loop = shift;
    my $handle = shift;
    $loop->stream_close($handle);
}

sub tcp_getsockname {
    my ($loop,$handle) = @_;
    $!  = 0;
    if ($handle->{delayed_error}) {
        $! = $handle->{delayed_error};
        return;
    }
    
    if (Rum::Loop::Stream::stream_fd($handle) < 0) {
        $! = EINVAL; #/* FIXME(bnoordhuis) -EBADF
        return;
    }
    
    my $name =  getsockname(Rum::Loop::Stream::stream_fh($handle));
    return if !$name;
    return $name;
}

sub tcp_getpeername {
    my ($loop,$handle) = @_;
    $!  = 0;
    if ($handle->{delayed_error}) {
        $! = $handle->{delayed_error};
        return;
    }
    
    if (Rum::Loop::Stream::stream_fd($handle) < 0) {
        $! = EINVAL; #/* FIXME(bnoordhuis) -EBADF
        return;
    }
    
    my $name =  getpeername(Rum::Loop::Stream::stream_fh($handle));
    return if !$name;
    return $name;
}


sub tcp_keepalive {
    my ($loop, $handle, $on, $delay) = @_;
    if (Rum::Loop::Stream::stream_fd($handle) != -1) {
        _tcp_keepalive(Rum::Loop::Stream::stream_fh($handle), $on, $delay)
            or return;
    }
    
    if ($on) {
        $handle->{flags} |= $TCP_KEEPALIVE;
    } else {
        $handle->{flags} &= ~$TCP_KEEPALIVE;
    }
    
    # TODO Store delay if uv__stream_fd(handle) == -1 but don't want to enlarge
    # uv_tcp_t with an int that's almost never used...
    
    return 1;
}

sub _tcp_keepalive {
    my ($fh, $on, $delay) = @_;
    #setsockopt($socket, IPPROTO_TCP, TCP_NODELAY, 1);
    if (!setsockopt($fh, SOL_SOCKET, SO_KEEPALIVE, $on)) {
        return;
    }
    
    ##FIXME
    ##ifdef TCP_KEEPIDLE
    #  if (on && setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, &delay, sizeof(delay)))
    #    return -errno;
    ##endif
    #
    #  /* Solaris/SmartOS, if you don't support keep-alive,
    #* then don't advertise it in your system headers...
    #*/
    #  /* FIXME(bnoordhuis) That's possibly because sizeof(delay) should be 1. */
    ##if defined(TCP_KEEPALIVE) && !defined(__sun)
    #  if (on && setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &delay, sizeof(delay)))
    #    return -errno;
    ##endif
    
    return 1;
}

1;

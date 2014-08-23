package Rum::Wrap::TCP;
use strict;
use warnings;
use Socket qw(AF_INET6 AF_INET);
use lib '../../';
use Rum::Wrap::Handle qw(close ref unref getHandleData);
use Rum::Loop ();
use Rum::Loop::Utils 'assert';
use Data::Dumper;
use Rum::Wrap::Stream qw(
    readStart
    readStop
    shutdown
    writeBuffer
    writeAsciiString
    writeUtf8String
    writeUcs2String
    writev
    stream
    UpdateWriteQueueSize
);

my $loop = Rum::Loop::default_loop();

sub new {
    my $handle_ = {};
    my $this = bless {}, shift;
    Rum::Wrap::Stream::StreamWrap($this,$handle_,1);
    $loop->tcp_init($handle_);
    $this->UpdateWriteQueueSize();
    $this->{'writev'} = 1;
    return $this;
}

sub connect {
    my $wrap = shift;
    my $req_wrap_obj = shift;
    my $ip_address = shift;
    my $port = shift;
    my $addr = $loop->ip4_addr($ip_address, $port) or return $!;
    
    my $req_wrap = {
        _req => $req_wrap_obj
    };
    
    $loop->tcp_connect($wrap->{handle__},
                       $req_wrap,
                        $addr,
                        \&AfterConnect) or return $!;
    
    return 0;
}

sub AfterConnect {
    my ($req, $status) = @_;
    my $req_wrap = $req;
    my $wrap = getHandleData($req->{handle});
    
    #The wrap and request objects should still be there.
    assert(defined $req_wrap);
    assert(defined $wrap);
    
    my $req_wrap_obj = $req_wrap->{_req};
    
    Rum::MakeCallback2($req_wrap_obj,'oncomplete', $status, $wrap, $req, 1,1);
    undef $req_wrap;
}

sub bind {
    my $wrap = shift;
    my $ip_address = shift;
    my $port = shift;
    
    my $addr = $loop->ip4_addr($ip_address, $port) or return $!;
    $loop->tcp_bind($wrap->{handle__},$addr,0) or return $!;
    
    return 0;
}

sub listen {
    my $wrap = shift;
    my $backlog = shift;
    $loop->listen($wrap->{handle__},
                    $backlog,
                    \&OnConnection) or return $!;
    return 0;
}

sub OnConnection {
    my ($handle, $status) = @_;
    my $tcp_wrap = getHandleData($handle);
    assert($tcp_wrap);
    assert($tcp_wrap->{handle__} == $handle);
    
    my $client_object = undef;
    if ($status == 0) {
        $client_object = __PACKAGE__->new();
        my $client_handle = $client_object->{handle__};
        $loop->accept($handle, $client_handle) or die $!;
    }
    
    Rum::MakeCallback2($tcp_wrap,'onconnection', $tcp_wrap, $status, $client_object);
}

sub open2 {
    my $wrap = shift;
    my $fh = shift;
    $loop->tcp_open($wrap->{handle__}, $fh) or die $!;
}

sub getsockname {
    my $wrap = shift;
    my $info = shift;
    my $addr = $loop->tcp_getsockname($wrap->{handle__}) or return $!;
    my $family = Socket::sockaddr_family($addr) or return $!;
    if ($family == AF_INET6) {
        my ($port, $ip6_address, $scope_id, $flowinfo) =
            Socket::unpack_sockaddr_in6($addr) or return $!;
        $info->{port} = $port;
        $info->{ip} = $ip6_address;
        $info->{family} = 'AF_INET6';
    } elsif ($family == AF_INET){
        my ($port, $ip_address)  = Socket::unpack_sockaddr_in($addr) or return $!;
        $info->{port} = $port;
        $info->{ip} = $ip_address;
        $info->{family} = 'AF_INET';
    }
    return 0;
}


sub setKeepAlive {
    my $wrap = shift;
    my $enable = shift;
    my $delay = shift;
    $loop->tcp_keepalive($wrap->{handle__}, $enable, $delay) or return $!;
    return 0;
}

1;

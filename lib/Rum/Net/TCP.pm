package Rum::Net::TCP;
use strict;
use warnings;
use lib '../../';
use Rum::Wrap::Handle qw(close ref unref);
use Rum::Loop ();
use Rum::Loop::Utils 'assert';
use Data::Dumper;

my $loop = Rum::Loop::default_loop();

sub new {
    my $handle_ = {};
    my $this = bless {}, shift;
    $loop->tcp_init($handle_);
    Rum::Wrap::Handle::HandleWrap($this,$handle_);
    return $this;
}

sub bind {
    my $wrap = shift;
    my $ip_address = shift;
    my $port = shift;
    
    my $addr = $loop->ip4_addr($ip_address, $port) or return $!;
    $loop->tcp_bind($wrap->{_handle},$addr,0) or return $!;
    
    return 0;
}


sub listen {
    my $wrap = shift;
    my $backlog = shift;
    $loop->listen($wrap->{_handle},
                    $backlog,
                    \&OnConnection) or return $!;
    return 0;
}

sub OnConnection {
    my ($handle, $status) = @_;
    my $tcp_wrap = $handle->{data};
    assert($tcp_wrap);
    assert($tcp_wrap->{_handle} == $handle);
    
    my $client_object = undef;
    if ($status == 0) {
        $client_object = Rum::Net::TCP->new();
        my $client_handle = $client_object->{_handle};
        $loop->accept($handle, $client_handle) or die $!;
    }
    
    $tcp_wrap->{'onconnection'}->($tcp_wrap,$status,$client_object);
    #$tcp_wrap->MakeCallback('onconnection', ARRAY_SIZE(argv), argv);
}

sub readStart {
    my $wrap = shift;
    $loop->read_start($wrap->{_handle}, \&OnRead) or die $!;
    return 0;
}

sub OnRead {
    my ($handle, $nread, $buf) = @_;
    OnReadCommon($handle, $nread, $buf, 0);
}

sub OnReadCommon {
    my ($handle, $nread, $buf, $pending) = @_;
    my $wrap = $handle->{data};
    $wrap->{onread}->($wrap, $nread, $buf);
    
}

#STREAM
sub WriteStringImpl {
    my $wrap = shift;
    my $encoding = shift;
    my $req_wrap_obj = shift;
    my $string = shift;
    
    my $buf = $loop->buf_init($string);
    #my $r = $loop->try_write($wrap->{_handle}, $buf, 1);
    $loop->write($req_wrap_obj, $wrap->{_handle}, $buf, 1, \&AfterWrite) or return $!;
    $req_wrap_obj->{bytes}  = 6;
    return 0;
}

sub writeUtf8String {
    my $wrap = $_[0]->{owner}->{_handle};
    return $wrap->WriteStringImpl('UTF8',@_);
}

sub AfterWrite {
    my ($req, $status) = @_;
    
    my $wrap = $req->{handle}->{data};
    return if !$wrap;
    #my $req_wrap = CONTAINER_OF(req, WriteWrap, req_);
    #my $wrap = req_wrap->wrap();
    #
    ##The wrap and request objects should still be there.
    #assert($req_wrap);
    assert($wrap);
    #
    ##Unref handle property
    #my $req_wrap_obj = $req_wrap;
    delete $req->{handle};
    #undef $req;
    #wrap->callbacks()->AfterWrite(req_wrap);
    #
    #Local<Value> argv[] = {
    #  Integer::New(status, env->isolate()),
    #  wrap->object(),
    #  req_wrap_obj,
    #  Undefined()
    #};
    #
    #const char* msg = wrap->callbacks()->Error();
    #if (msg != NULL)
    #  argv[3] = OneByteString(env->isolate(), msg);
    #
    #req_wrap->MakeCallback(env->oncomplete_string(), ARRAY_SIZE(argv), argv);
    #
    #req_wrap->~WriteWrap();
    #delete[] reinterpret_cast<char*>(req_wrap);
    $req->{oncomplete}->($status,$wrap,$req,'');
}


sub connect {
    
    my $wrap = shift;
    my $req_wrap_obj = shift;
    my $ip_address = shift;
    my $port = shift;
    my $addr = $loop->ip4_addr($ip_address, $port) or return $!;
    
    #my req_wrap = new ConnectWrap(env,
    #                req_wrap_obj,
    #                AsyncWrap::PROVIDER_CONNECTWRAP);
    
    my $req_wrap = {
        _req => $req_wrap_obj
    };
    
    $loop->tcp_connect($wrap->{_handle},
                       $req_wrap,
                        $addr,
                        \&AfterConnect) or die $!;
    #req_wrap->Dispatched();
  #  if (err)
  #    delete req_wrap;
  #}
    return 0;
}

sub AfterConnect {
    my ($req, $status) = @_;
    my $req_wrap = $req;
    my $wrap = $req->{handle}->{data};
    
    #assert($req_wrap == $wrap);

    #The wrap and request objects should still be there.
    assert(defined $req_wrap);
    assert(defined $wrap);

    my $req_wrap_obj = $req_wrap->{_req};
    
    my @argv = (
        $status,
        $wrap,
        $req_wrap_obj,
        1,
        1
    );
    
    Rum::MakeCallback($req_wrap_obj, 'oncomplete', @argv);
    #$req_wrap_obj->{'oncomplete'}->($status,$wrap,$req,1,1);
    #req_wrap->MakeCallback(env->oncomplete_string(), ARRAY_SIZE(argv), argv);
    undef $req_wrap;
}


sub shutdown {
    my $wrap = shift;
    assert(CORE::ref $wrap);
    my $req_wrap_obj = shift;
    $loop->shutdown($req_wrap_obj, $wrap->{_handle}, \&AfterShutdown) or return $!;
    return 0;
}


sub AfterShutdown {
    my ($req, $status) = @_;
    my $req_wrap = $req;
    my $wrap = $req->{handle}->{data};
    $req_wrap->{oncomplete}->($status,$wrap,$req_wrap);
    undef $req_wrap;
}


sub is_named_pipe {
    return shift->{type} eq 'NAMED_PIPE';
}

1;

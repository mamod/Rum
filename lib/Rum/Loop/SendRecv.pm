package Rum::Loop::SendRecv;
use strict;
use warnings;
use Config;
use Socket;
use Data::Dumper;
use Rum::Loop::Flags qw[:Platform :Stream];
use Rum::Loop::Utils 'assert';
use Rum::Loop::Core;
use FileHandle;
use Socket;
use Fcntl;
use POSIX ':errno_h';

use base qw/Exporter/;
our @EXPORT = qw (
    msghdr
    recvmsg
    sendmsg
);

my ($SYS_sendmsg,$SYS_recvmsg,$SYS_fcntl,$SYS_socketcall,$BUFLEN);

#copied from Sys::Syscall
my $loaded_syscall = 0;
sub _load_syscall {
    # props to Gaal for this!
    return if $loaded_syscall++;
    my $clean = sub {
        delete @INC{qw<syscall.ph asm/unistd.ph bits/syscall.ph
                        _h2ph_pre.ph sys/syscall.ph>};
    };
    $clean->(); # don't trust modules before us
    my $rv = eval { require 'syscall.ph'; 1 } || eval { require 'sys/syscall.ph'; 1 };
    $clean->(); # don't require modules after us trust us
    return $rv;
}

if ($isWin) {
    $BUFLEN = 768;
    *recvmsg = \&__win_recvmsg;
    *sendmsg = \&__win_sendmsg;
} else {
    $BUFLEN = 768;
    my ($sysname, $nodename, $release, $version, $machine) = POSIX::uname();
    if ($^O eq "linux") {
        if ($machine =~ m/^i[3456]86$/) {
            $SYS_socketcall = 102;
            $SYS_fcntl      = 55;
        } else {
            if ($machine eq "x86_64") {
                $SYS_sendmsg = 46;
                $SYS_recvmsg = 47;
                $SYS_fcntl   = 72;
            } else {
                _load_syscall();
                $SYS_sendmsg = eval { &SYS_sendmsg; } || 0;
                $SYS_recvmsg = eval { &SYS_recvmsg; } || 0;
                $SYS_fcntl   = eval { &SYS_fcntl;   } || 0;
            }
        }
    } elsif ($^O eq "freebsd"){
        $SYS_fcntl   = 92;
        $SYS_sendmsg = 28;
        $SYS_recvmsg = 27;
    }
    
    if ($SYS_socketcall) {
        *sys_sendmsg = sub { syscall( $SYS_socketcall, 16, pack("iPi", @_)) };
        *sys_recvmsg = sub { syscall( $SYS_socketcall, 17, pack("iPi", @_)) };
    } elsif ($SYS_sendmsg) {
        *sys_sendmsg = sub { syscall($SYS_sendmsg, @_) };
        *sys_recvmsg = sub { syscall($SYS_recvmsg, @_) };
    } else {
        *sys_sendmsg = sub {
            $! = EINVAL;
            return -1;
        };
        
        *sys_recvmsg = sub {
            $! = EINVAL;
            return -1;
        };
    }
    
    *recvmsg = \&__recvmsg;
    *sendmsg = \&__sendmsg;
}

## linux / freebsd
## original work from
## http://duck.noduck.net/20080522/sendmsgrecvmsg-with-perl-on-linux
use constant BUFLEN => 16 * 1024;

# iov: iov_base, iov_len
use constant IOV_PACK => 'P'.BUFLEN.'L!';
use constant IOV_LEN => length(pack(IOV_PACK, 0, 0));

# cmsghdr: cmsg_len, cmsg_level, cmsg_type
use constant CMSGHDR_PACK => 'L!ii*';
use constant CMSGHDR_LEN => length(pack(CMSGHDR_PACK, 0, 0, 0));

# msghdr: msg_name, msg_namelen, msg_iov, msg_iovlen,
# msg_control, msg_controllen, msg_flags
use constant MSGHDR_PACK => 'PL!P'.IOV_LEN.'L!P'.CMSGHDR_LEN.'L!i';

my $CMSG_FD_SIZE = 64 * $Config{intsize};

#define CMSG_ALIGN(len) ( ((len)+sizeof(long)-1) & ~(sizeof(long)-1) )
sub CMSG_ALIGN {
    my $len = shift;
    return (($len) + $Config{longsize} -1 ) & ~( $Config{longsize} - 1);
}

#define CMSG_SPACE(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + CMSG_ALIGN(len))
sub CMSG_SPACE {
    my $len = shift;
    return CMSG_ALIGN(CMSGHDR_LEN) + CMSG_ALIGN($len);
}

#define CMSG_LEN(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
sub CMSG_LEN {
    my $len = shift;
    return CMSG_ALIGN(CMSGHDR_LEN) + ($len);
}

sub sizeof_cmsg_space {
    my $t = shift;
    return CMSG_SPACE(length $t);
}

sub get_fopen_mode {
    my $fd=$_[0];
    
    my $rc= syscall($SYS_fcntl, $fd, F_GETFL);
    return undef if $rc < 0;
    my $acc = ($rc&(O_WRONLY|O_RDONLY|O_RDWR));
    
    my $app = ($rc&O_APPEND);
    if ($acc == O_RDONLY) { return "r"; }
    if ($acc == O_WRONLY and !$app)  { return "w"; }
    if ($acc == O_WRONLY and $app) { return "a"; }
    if ($acc == O_RDWR and !$app) { return "w+"; }
    if ($acc == O_RDWR and $app) { return "a+"; }
}

sub __sendmsg {
    my ($sock, $buf, $fds, $flags) = @_;
    
    my @fds_to_send = ref $fds ? @{$fds} : ($fds);
    my $iov_len = 1;
    
    my $msg_controllen = CMSG_LEN(length pack("i*",@fds_to_send));
    my $msg_control = pack (CMSGHDR_PACK, ($msg_controllen,SOL_SOCKET,1, @fds_to_send));
    
    my $iov    = pack (IOV_PACK, ($buf, length $buf));
    my $msghdr = pack (MSGHDR_PACK,(undef,0,$iov,$iov_len,$msg_control,$msg_controllen,0));
    
    my $n;
    $! = 0;
    do {
        $n = sys_sendmsg(fileno $sock, $msghdr, $flags);
    } while ($n < 0 && $! == EINTR);
    
    if ($n < 0) {
        return;
    }
    return $n;
}

sub __recvmsg {
    
    my ($sock, $buff) = @_;
    my $cmsg_space = "\0" x CMSG_SPACE(128);
    my $buffer = "\0" x BUFLEN;
    my $buf_iov = pack(IOV_PACK, ($buffer, BUFLEN));
    my $msghdr  = pack(MSGHDR_PACK,("",0,$buf_iov,1,$cmsg_space,
                                    sizeof_cmsg_space($cmsg_space),0));
    
    my $n = -1;
    $! = 0;
    do {
       $n = sys_recvmsg(fileno $sock,$msghdr,0);
    } while ($n < 0 && $! == EINTR);
    
    if ($n < 0) {
        return;
    }
    
    my $CMSGHDR_LEN = length(pack(CMSGHDR_PACK, map { 0 } (0 .. 28)));
    my $MSGHDR_PACK = 'PL!P'.IOV_LEN.'L!P'.$CMSGHDR_LEN.'L!i';
    
    my @data = unpack ($MSGHDR_PACK, $msghdr);
    my @rec = unpack(CMSGHDR_PACK, $data[4]);
    my $cmshdrsize = $rec[0];
    
    #skip cmsg_len, cmsg_level, cmsg_type
    my $i = 3;
    while ($cmshdrsize > CMSGHDR_LEN) {
        my $fd = $rec[$i++];
        open(my $new, "+<&=", $fd) or die $!;
        Rum::Loop::Core::nonblock($new, 1);
        Rum::Loop::Core::cloexec ($new, 1);
        $new->autoflush(1);
        push @{$buff->{fds}}, $new;
        $cmshdrsize -= length(pack("L!"));
    }
    
    $buff->{base} = substr $buffer, 0, $n;
    undef $buffer;
    undef $msghdr;
    $buff->{len} = $n;
    
    return $n;
}

####Windows sendmsg/recvmsg
my $INVALID_SOCKET = -1;
my $IPPROTO_TCP = 6;
my $IPC_RAW_DATA        = 0x0001;
my $IPC_TCP_SERVER      = 0x0002;
my $IPC_TCP_CONNECTION  = 0x0004; 
my $HANDLE_FLAG_INHERIT = 0x00000001;

my $sig_len = length("##\0\0") + length(pack("ii")) + $BUFLEN + 2;

sub __win_recvmsg {
    my ($sock, $buf) = @_;
    my $data;
    my $to_read_length;
    my @rec_handles;
    
    while (1) {
        my $string;
        $! = 0;
        recv $sock,$data, $BUFLEN, MSG_PEEK;
        
        $to_read_length = $data ? length $data : 0;
        if ($to_read_length == 0) {
            return if $! != 0;
            return 0;
        }
        
        if ($to_read_length >= $BUFLEN) {
            my $nread = sysread($sock, $string, $BUFLEN);
            return if !defined $nread;
            if ($nread != $BUFLEN){
                $buf->{base} = $string;
                $buf->{len} = $nread;
                return $nread;
            }
            
            my $newsock = Rum::Loop::Core::WSASocket(AF_INET,
                                                 SOCK_STREAM,
                                                 $IPPROTO_TCP,
                                                 $string, 0, 0);
            
            if (!defined $newsock || $newsock == $INVALID_SOCKET) {
                die $^E;
            } else {
                my $new = new FileHandle;
                Rum::Loop::Core::OsFHandleOpen($new, $newsock, 'rw') or die $^E;
                Rum::Loop::Core::nonblock($new, 1);
                $new->autoflush(1);
                push @{$buf->{fds}}, $new;
            }
        } else {
            last;
        }
    }
    
    done : {
        my $nread = sysread($sock, my $string, $to_read_length);
        $buf->{base} = $string;
        $buf->{len} = $nread;
        return $nread;
    }
}

sub __win_sendmsg {
    my ($sock, $string, $fds, $child_pid) = @_;
    my @fds = ref $fds eq 'ARRAY' ? @{$fds} : ($fds);
    $child_pid ||= $$;
    
    foreach my $fd (@fds){
        my $fhandle = Rum::Loop::Core::FdGetOsFHandle( $fd ) or die $^E;
        my $buf = " " x $BUFLEN;
        Rum::Loop::Core::WSADuplicateSocketW($fhandle, $child_pid, $buf ) && die $^E;
        my $sent = send($sock, $buf, 0) or return;
        die "could not send sock info" if $sent != $BUFLEN;
    }
    
    return syswrite $sock, $string, length $string;
}

1;

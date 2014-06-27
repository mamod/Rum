package Rum::Loop::Pipe;
use strict;
use warnings;
use Socket;
use Rum::Loop::Queue;
use Data::Dumper;
use POSIX qw(:errno_h);
use Rum::Loop::Flags qw(:Stream :IO :Errors :Platform);
use Rum::Loop::Utils 'assert';
use Socket;

use base qw/Exporter/;
our @EXPORT = qw (
    pipe_init
    pipe_open
    pipe_bind
    pipe_listen
    pipe_close
    pipe_connect
    pipe_pending_type
    pipe_pending_count
);

if ($isWin) {
    require Rum::Loop::Pipe::Win32;
} else {
    require Rum::Loop::Pipe::UNIX;
}

sub pipe_init {
    my ($loop, $handle, $ipc) = @_;
    $loop->stream_init($_[1], 'NAMED_PIPE');
    $_[1]->{shutdown_req} = undef;
    $_[1]->{connect_req} = undef;
    $_[1]->{pipe_fname} = undef;
    $_[1]->{ipc} = $ipc;
    $_[1]->{ipc_pid} = 0;
    #$_[1]->{loop} = $loop;
    return 1;
}

sub pipe_open {
    my ($loop, $handle, $fh) = @_;
    return Rum::Loop::stream_open($handle,
            $fh,
            $STREAM_READABLE | $STREAM_WRITABLE);
}

sub pipe_listen {
    my ($loop, $handle, $backlog, $cb) = @_;
    if (Rum::Loop::Stream::stream_fd($handle) == -1) {
        $! = EINVAL;
        return;
    }

    if (!listen(Rum::Loop::Stream::stream_fh($handle), $backlog)) {
        return;
    }
    
    $handle->{connection_cb} = $cb;
    $handle->{io_watcher}->{cb} = \&Rum::Loop::Stream::server_io;
    $loop->io_start($handle->{io_watcher}, $POLLACCEPT);
    return 1;
}

sub pipe_close {
    my $loop = shift;
    my $handle = shift;
    if (defined $handle->{pipe_fname}) {
        #Unlink the file system entity before closing the file descriptor.
        #Doing it the other way around introduces a race where our process
        #unlinks a socket with the same name that's just been created by
        #another thread or process.
        
        unlink($handle->{pipe_fname});
        undef $handle->{pipe_fname};
    }
    
    $loop->stream_close($handle);
}

sub pipe_pending_count {
    my $loop = shift;
    my $handle = shift;
    
    if (!$handle->{ipc}){
        return 0;
    }
    
    if ($handle->{accepted_fd} == -1){
        return 0;
    }
    
    if ( !@{$handle->{queued_fds}} ){
        return 1;
    }
    
    return scalar @{$handle->{queued_fds}};
}

sub pipe_pending_type {
    my ($loop, $handle) = @_;
    
    if (!$handle->{ipc}) {
        return 'UNKNOWN_HANDLE';
    }
    
    if ($handle->{accepted_fd} == -1) {
        return 'UNKNOWN_HANDLE';
    } else {
        my $type = __handle_type($handle->{accepted_fh});
        return $type;
    }
}

sub __handle_type {
    my $fh = shift;
    my $sockaddr = getsockname($fh);
    
    if (!defined $sockaddr) {
        return 'UNKNOWN_HANDLE';
    }
    
    my $sock_opt = getsockopt($fh, SOL_SOCKET, SO_TYPE);
    if (!defined $sock_opt) {
        return 'UNKNOWN_HANDLE';
    }
    my $type = unpack("I",$sock_opt);
    my $family = sockaddr_family $sockaddr or return 'UNKNOWN_HANDLE';
    
    if ($type == SOCK_STREAM) {
        if ($family == AF_UNIX) {
            return 'NAMED_PIPE';
        } elsif ($family == AF_INET || $family == AF_INET6 ){
            return 'TCP';
        }
    }

    if ($type == SOCK_DGRAM &&
        ($family == AF_INET || $family == AF_INET6)) {
        return 'UDP';
    }

    return 'UNKNOWN_HANDLE';
}

1;

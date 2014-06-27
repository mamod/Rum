package Rum::Loop::Flags;
use warnings;
use strict;
use Fcntl;
use Errno;
use Scalar::Util qw/dualvar/;

use base qw/Exporter/;
our %EXPORT_TAGS = (
    Process => [qw(
        $PROCESS_SETUID
        $PROCESS_SETGID
        $PROCESS_WINDOWS_VERBATIM_ARGUMENTS
        $PROCESS_DETACHED
        $PROCESS_WINDOWS_HIDE
    )],
    Handle =>[qw(
        $HANDLE_CLOSING
        $HANDLE_REF
        $HANDLE_ACTIVE
        $HANDLE_INTERNAL
    )],
    Stdio =>[ qw(
        $IGNORE
        $CREATE_PIPE
        $INHERIT_FD
        $INHERIT_STREAM
        $READABLE_PIPE
        $WRITABLE_PIPE
    )],
    Stream => [qw(
        $STREAM_READING 
        $STREAM_SHUTTING
        $STREAM_SHUT
        $STREAM_READABLE
        $STREAM_WRITABLE
        $STREAM_BLOCKING
        $STREAM_READ_PARTIAL
        $STREAM_READ_EOF
        $EOF
        $TCP_NODELAY
        $TCP_KEEPALIVE
    )],
    IO =>[qw(
        $POLLIN
        $POLLOUT
        $POLLHUP
        $POLLERR
        $POLLACCEPT
        $NONBLOCK
        $CLOEXEC
        $SELECT
    )],
    Event => [qw(
        $EPOLL
        $KQUEUE
    )],
    Platform => [qw(
        $isWin
        $isApple
        $isLinux
        $isFreebsd
        $ACCEPT4
    )],
    Run => [qw(
        $CLOSING
        $CLOSED
        $RUN_NOWAIT
        $RUN_ONCE
        $RUN_DEFAULT
    )],
    Errors => [qw(
        $ECANCELED
        $EAGAIN
    )]
);

our @EXPORT = qw (
    $CLOSING
    $CLOSED
    $RUN_NOWAIT
    $RUN_ONCE
    $RUN_DEFAULT
    $STREAM_READING 
    $STREAM_SHUTTING
    $STREAM_SHUT
    $STREAM_READABLE
    $STREAM_WRITABLE
    $STREAM_BLOCKING
    $STREAM_READ_PARTIAL
    $STREAM_READ_EOF
    $EOF
    $TCP_NODELAY
    $TCP_KEEPALIVE
    $HANDLE_CLOSING
    $HANDLE_REF
    $HANDLE_ACTIVE
    $HANDLE_INTERNAL
    $SELECT
    $POLLIN
    $POLLOUT
    $POLLHUP
    $POLLERR
    $POLLACCEPT
    $NONBLOCK
    $CLOEXEC
    $EPOLL
    $KQUEUE
    $isWin
    $isApple
    $isFreebsd
    $isLinux
    $ACCEPT4
    $ECANCELED
    $EAGAIN
    $PROCESS_SETUID
    $PROCESS_SETGID
    $PROCESS_WINDOWS_VERBATIM_ARGUMENTS
    $PROCESS_DETACHED
    $PROCESS_WINDOWS_HIDE
    $IGNORE
    $CREATE_PIPE
    $INHERIT_FD
    $INHERIT_STREAM
    $READABLE_PIPE
    $WRITABLE_PIPE
);

# Stream ========================================================================
our $STREAM_READING       = 0x04;   # uv_read_start() called.
our $STREAM_SHUTTING      = 0x08;   # uv_shutdown() called but not complete.
our $STREAM_SHUT          = 0x10;   # Write side closed.
our $STREAM_READABLE      = 0x20;   # The stream is readable
our $STREAM_WRITABLE      = 0x40;   # The stream is writable
our $STREAM_BLOCKING      = 0x80;   # Synchronous writes.
our $STREAM_READ_PARTIAL  = 0x100,  # read(2) read less than requested.
our $STREAM_READ_EOF      = 0x200,  # read(2) read EOF.
our $EOF = dualvar -4095, "End of stream";
our $TCP_NODELAY  =  0x400; # Disable Nagle.
our $TCP_KEEPALIVE = 0x800; # Turn on keep-alive.

# Process Flags =========================================================

#* Set the child process' user id. The user id is supplied in the `uid` field
#* of the options struct. This does not work on windows; setting this flag
#* will cause uv_spawn() to fail.
our $PROCESS_SETUID = (1 << 0);

# Set the child process' group id. The user id is supplied in the `gid`
# field of the options struct. This does not work on windows; setting this
# flag will cause uv_spawn() to fail.

our $PROCESS_SETGID = (1 << 1);

# Do not wrap any arguments in quotes, or perform any other escaping, when
# converting the argument list into a command line string. This option is
# only meaningful on Windows systems. On unix it is silently ignored.

our $PROCESS_WINDOWS_VERBATIM_ARGUMENTS = (1 << 2);
  
#* Spawn the child process in a detached state - this will make it a process
#* group leader, and will effectively enable the child to keep running after
#* the parent exits. Note that the child process will still keep the
#* parent's event loop alive unless the parent process calls uv_unref() on
#* the child's process handle.

our $PROCESS_DETACHED = (1 << 3);

#* Hide the subprocess console window that would normally be created. This
#* option is only meaningful on Windows systems. On unix it is silently
#* ignored.

our $PROCESS_WINDOWS_HIDE = (1 << 4);

# run ===================================================================
our $RUN_DEFAULT = 0;
our $RUN_ONCE    = 1;
our $RUN_NOWAIT  = 2;
our $CLOSING     = 0x01;
our $CLOSED      = 0x02;

# Stdio =================================================================
our $IGNORE = 0x00;
our $CREATE_PIPE = 0x01;
our $INHERIT_FD = 0x02;
our $INHERIT_STREAM = 0x04;

#When UV_CREATE_PIPE is specified, UV_READABLE_PIPE and UV_WRITABLE_PIPE
#determine the direction of flow, from the child process' perspective. Both
#flags may be specified to create a duplex data stream.

our $READABLE_PIPE = 0x10;
our $WRITABLE_PIPE = 0x20;

# Handle ================================================================
our $HANDLE_CLOSING  = 0;
our $HANDLE_REF      = 0x2000;
our $HANDLE_ACTIVE   = 0x4000;
our $HANDLE_INTERNAL = 0x8000;

# IO ====================================================================
our $POLLIN  = 0;
our $POLLOUT = 0;
our $POLLHUP = 0;
our $POLLERR = 0;
our $POLLACCEPT = 0;
our $NONBLOCK = eval "O_NONBLOCK;" || 0;
our $CLOEXEC = eval "FD_CLOEXEC;" || 0;

# Platform ==============================================================
our $isWin = $^O eq 'MSWin32';
our $isApple = 0;
our $isLinux = 0;
our $isFreebsd = $^O eq 'freebsd';

## Events Backend =======================================================
our $SELECT = 0;
our $WINAPI     = eval "use Win32::API; 1";
our $EPOLL = 0;


##fall back to select
if ($isWin || $isFreebsd) {
    require Rum::Loop::IO::Select;
    $POLLIN = Rum::Loop::IO::Select::EPOLLIN();
    $POLLOUT = Rum::Loop::IO::Select::EPOLLOUT();
    $POLLERR = Rum::Loop::IO::Select::EPOLLERR();
    $POLLHUP = Rum::Loop::IO::Select::EPOLLHUP();
    $POLLACCEPT = $POLLIN;
    $SELECT = 1;
} elsif (1){
    require Rum::Loop::IO::EPoll;
    $POLLIN = Rum::Loop::IO::EPoll::EPOLLIN();
    $POLLOUT = Rum::Loop::IO::EPoll::EPOLLOUT();
    $POLLERR = Rum::Loop::IO::EPoll::EPOLLERR();
    $POLLHUP = Rum::Loop::IO::EPoll::EPOLLHUP();
    $POLLACCEPT = $POLLIN;
    $EPOLL = 1;
}

our $KQUEUE     = eval "use IO::KQueue; 1";
our $ACCEPT4    = eval "use Linux::Socket::Accept4; 1";

## ERRORS ===============================================================
our $ECANCELED;       #Operation canceled (POSIX.1)
if (!exists &Errno::ECANCELED) {
    $ECANCELED = dualvar 4081,'Operation canceled';
} else {
    $! = &Errno::ECANCELED;
    $ECANCELED = $!;
}

our $EAGAIN = 'Resource temporarily unavailable';
if (!exists &Errno::EAGAIN) {
    $EAGAIN = dualvar 11, $EAGAIN;
} else {
    $! = &Errno::EAGAIN;
    $EAGAIN = $!;
}

1;

package Rum::Loop::TTY;
use strict;
use warnings;
use Rum::Loop::Flags qw(:Stream);
use Rum::Loop::Stream ();
use FileHandle;
use POSIX ':errno_h';

use base qw/Exporter/;
our @EXPORT = qw (
    tty_init
    tty_get_winsize
);

if ($^O eq 'MSWin32') {
    require Rum::Loop::TTY::Win32;
} else {
    require Rum::Loop::TTY::UNIX;
}

sub tty_init {
    
    my ($loop, $tty, $fh, $readable) = @_;
    my $flags = 0;
    my $newfh = 0;
    my $r = 0;
    
    $loop->stream_init($tty, 'TTY');
    
    #Reopen the file descriptor when it refers to a tty. This lets us put the
    #tty in non-blocking mode without affecting other processes that share it
    #with us.
    #Example: `node | cat` - if we put our fd 0 in non-blocking mode, it also
    #affects fd 1 of `cat` because both file descriptors refer to the same
    #struct file in the kernel. When we reopen our fd 0, it points to a
    #different struct file, hence changing its properties doesn't affect
    #other processes.
    
    if ( -t $fh ) {
        
        #$r = uv__open_cloexec("/dev/tty", O_RDWR);
        #
        #if ($r < 0) {
        #    #fallback to using blocking writes
        #    if (!$readable) {
        #        $flags |= $STREAM_BLOCKING;
        #    }
        #    goto skip;
        #}
        #
        #$newfh = $r;
        #
        #$r = uv__dup2_cloexec($newfh, $fh);
        #if ($r < 0 && $r != EINVAL) {
        #    #EINVAL means newfd == fd which could conceivably happen if another
        #    #thread called close(fd) between our calls to isatty() and open().
        #    #That's a rather unlikely event but let's handle it anyway.
        #    
        #    uv__close($newfh);
        #    return $r;
        #}
        #
        #$fh = $newfh;
    }
    
    skip:{
        $r = 0;
    #if defined(__APPLE__)
        #r = uv__stream_try_select((uv_stream_t*) tty, &fd);
        #if (r) {
        # 
        #    if (newfd != -1){
        #        uv__close(newfd);
        #    }
        #    
        #    return r;
        #}
    #endif
    };
    
    if ($readable) {
        $flags |= $STREAM_READABLE;
    } else {
        $flags |= $STREAM_WRITABLE;
    }
    
    if (!($flags & $STREAM_BLOCKING)) {
        Rum::Loop::Core::nonblock($fh, 1);
    }
    
    Rum::Loop::Stream::stream_open($tty, $fh, $flags);
    $tty->{mode} = 0;
    
    return 1;
}


1;

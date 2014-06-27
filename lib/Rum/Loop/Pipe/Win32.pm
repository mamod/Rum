package Rum::Loop::Pipe::Win32;

package 
		Rum::Loop::Pipe;
use strict;
use warnings;
use Socket;
use Rum::Loop::Queue;
use Data::Dumper;
use POSIX qw(:errno_h);
use Rum::Loop::Flags qw(:Stream :IO :Errors :Platform $CLOSING $CLOSED $KQUEUE);
use Rum::Loop::Utils 'assert';
#AF_INET
my $global_pipes = {

};

sub pipe_bind {
    my ($loop, $handle, $name) = @_;
    $name = 9090;
    my $pipe_fname = undef;
    my $sockfh;
    my $bound = 0;
    my $error = EINVAL;
    
    #Already bound?
    if (Rum::Loop::Stream::stream_fd($handle) >= 0) {
		$! = $error;
        return;
    }
    
    #Make a copy of the file name, it outlives this function's scope.
    $pipe_fname = $name;
    if (!defined $pipe_fname) {
        $error = ENOMEM;
        goto out;
    }
	
    #We've got a copy, don't touch the original any more.
	undef $name;
    
	$sockfh = Rum::Loop::TCP::_socket(AF_INET, SOCK_STREAM, 0);
	if (!$sockfh) {
		$error = $!;
		goto out;
	}
	
    if (!bind($sockfh, pack_sockaddr_in($pipe_fname,inet_aton("localhost") ))) {
        if ($! == ENOENT) {
            $! = EACCES;
        }
		$error = $!;
        goto out;
    }
    
    $bound = 1;
    
    #Success.
    $handle->{pipe_fname} = $pipe_fname; # Is a strdup'ed copy.
    $handle->{io_watcher}->{fd} = fileno $sockfh;
    $handle->{io_watcher}->{fh} = $sockfh;
    return 1;
    
    out: {
        if ($bound) {
            #unlink() before uv__close() to avoid races. */
            assert(defined $pipe_fname);
            unlink($pipe_fname);
        }
		
        Rum::Loop::Core::__close($sockfh);
        undef $pipe_fname;
		$! = $error;
        return;
    }
}


sub pipe_connect {
    my ($loop, $req, $handle, $name, $cb) = @_;
	$name = 9090;
	
    my $error = 0;
	my $sock;
	
    my $new_sock = (Rum::Loop::Stream::stream_fd($handle) == -1);
    $error = EINVAL;
	
	if ($new_sock) {
		$sock = Rum::Loop::TCP::_socket(AF_INET, SOCK_STREAM, 0);
		if (!$sock) {
			$error = $!;
			goto out;
		}
		Rum::Loop::Core::nonblock($sock, 0);
		$handle->{io_watcher}->{fh} = $sock;
        $handle->{io_watcher}->{fd} = fileno $sock;
	}
	
	my $r;
    do {
        $r = connect(Rum::Loop::Stream::stream_fh($handle),
                pack_sockaddr_in($name,inet_aton("localhost") ));
    } while (!$r && $! == EINTR);
	
    if (!$r && $! != EINPROGRESS) {
		$error = $!;
        goto out;
    }
    
    $error = 0;
    if ($new_sock) {
		Rum::Loop::Core::nonblock($sock, 1);
        if (!Rum::Loop::Stream::stream_open($handle,
                          Rum::Loop::Stream::stream_fh($handle),
                          $STREAM_READABLE | $STREAM_WRITABLE)){
			$error = $!;
		}
    }
    
    if ($error == 0) {
        $loop->io_start($handle->{io_watcher}, $POLLIN | $POLLOUT);
    }
    
    out: {
        $handle->{delayed_error} = $error;
        $handle->{connect_req} = $req;
        
        $loop->req_init($req, 'CONNECT');
        $req->{handle} = $handle;
        $req->{cb} = $cb;
        $req->{queue} = QUEUE_INIT($req);
		
        #Force callback to run on next tick in case of error. */
        if (!$r) {
            $loop->io_feed($handle->{io_watcher});
        }
    };
    
    return 1;
}


1;

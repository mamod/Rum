package Rum::Loop::Signal;
use strict;
use warnings;

use Rum::Loop::Process ();
use Rum::Loop::IO ();
use Rum::RBTree;
use Rum::Loop::Flags qw($CLOSING $CLOSED :IO);
use Rum::Loop::Utils 'assert';
use IO::Handle;
use Config;
use Data::Dumper;
use POSIX qw(:errno_h :signal_h);
use Scalar::Util qw(looks_like_number);

use base qw/Exporter/;
our @EXPORT = qw (
    signal_init
    signal_start
    signal_stop
    signal_close
);


defined $Config{sig_name} || die "No sigs?";
our %signo;
our %signame;
my $i = 0;
foreach my $name ( split(' ', $Config{sig_name})) {
    $signo{$name} = $i; $signame{$i} = $name; $i++;
}

my $signal_tree = Rum::RBTree->new(\&signal_compare);
my $signal_lock_pipefd = [-1,-1];

my $g_handles = {};
my $g_counter = 0;
signal_global_init();

sub signal_compare {
    my ($w1, $w2) = @_;
    # Compare signums first so all watchers with the same signnum end up
    # adjacent.
    
    return -1 if ($w1->{signum} < $w2->{signum});
    return 1 if ($w1->{signum} > $w2->{signum});
    
    # Sort by loop pointer, so we can easily look up the first item after
    # { .signum = x, .loop = NULL }.
    # if (w1->loop < w2->loop) return -1;
    # if (w1->loop > w2->loop) return 1;
    # if (w1 < w2) return -1;
    # if (w1 > w2) return 1;
    
    return 0;
}

sub signal_init {
    my ($loop, $handle) = @_;
    my $err;
    
    signal_loop_once_init($loop) or die $!;
    
    $loop->handle_init($_[1], 'SIGNAL');
    $_[1]->{signum} = 0;
    $_[1]->{caught_signals} = 0;
    $_[1]->{dispatched_signals} = 0;
    $_[1]->{loop} = $loop;
    return 1;
}

sub signal_loop_once_init {
    my $loop = shift;
    
    # Return if already initialized.
    if ($loop->{signal_pipefd}->[0] != -1) {
        return 1;
    }
    
    Rum::Loop::Core::make_pipe($loop->{signal_pipefd},
                    1) or return;
    
    $loop->io_init(
            $loop->{signal_io_watcher},
            $loop->{signal_pipefd}->[0],
            \&signal_event);
    
    $loop->io_start($loop->{signal_io_watcher}, $POLLIN);
    
    return 1;
}

sub signal_event {
    my ($loop, $w, $events) = @_;
    my $fh = $loop->{signal_pipefd}->[0];
    
    while (my $line = <$fh>) {
        chomp $line;
        my $msg = $g_handles->{$line};
        next if !$msg;
        my $handle = $msg->{handle};
        if ($msg->{signum} == $handle->{signum} ) {
            assert(!($handle->{flags} & $CLOSING));
            $handle->{signal_cb}->($handle, $handle->{signum});
        }
        
        $handle->{dispatched_signals}++;
        
        # If uv_close was called while there were caught signals that were not
        # yet dispatched, the uv__finish_close was deferred. Make close pending
        # now if this has happened.
        
        if (($handle->{flags} & $CLOSING) &&
            ($handle->{caught_signals} == $handle->{dispatched_signals})) {
            $loop->make_close_pending($handle);
        }
    }
}


sub signal_first_handle {
    my $signum = shift;   
    #This function must be called with the signal lock held.
    my $lookup = {};
    
    $lookup->{signum} = $signum;
    $lookup->{loop} = undef;
    
    my $handle = $signal_tree->nfind($lookup);
    if ($handle && $handle->{signum} == $signum){
        return $handle;
    }
    
    return;
}

sub signal_close {
    my $loop = shift;
    my $handle = shift;
    _signal_stop($loop,$handle);
    
    # If there are any caught signals "trapped" in the signal pipe, we can't
    # call the close callback yet. Otherwise, add the handle to the finish_close
    # queue.
    if ($handle->{caught_signals} == $handle->{dispatched_signals}) {
        $loop->make_close_pending($handle);
    }
}

sub _signal_stop {
    my $loop = shift;
    my $handle = shift;
    
    #If the watcher wasn't started, this is a no-op. */
    if ($handle->{signum} == 0) {
        return 1;
    }
    
    signal_block_and_lock();
    
    my $removed_handle = $signal_tree->remove($handle);
    #assert($removed_handle == $handle);
    #(void) removed_handle;

    #Check if there are other active signal watchers observing this signal. If
    #not, unregister the signal handler.
    
    if (!signal_first_handle($handle->{signum})){
        signal_unregister_handler($handle->{signum});
    }
    
    signal_unlock_and_unblock();
    
    $handle->{signum} = 0;
    $loop->handle_stop($handle);
    return 1;
}

sub signal_stop {
    my $loop = shift;
    my $handle = shift;
    assert(!($handle->{flags} & ($CLOSING | $CLOSED)));
    _signal_stop($loop,$handle);
}

sub signal_unregister_handler {
    my $signum = shift;
    $SIG{$signame{$signum}} = 'IGNORE';
}

sub signal_register_handler {
    my $signum = shift;
    my $sig = $signame{$signum};
    $SIG{$sig} = \&signal_handler;
    return 1;
}

sub signal_global_init {
    if (!Rum::Loop::Core::make_pipe($signal_lock_pipefd, 0)){
        die;
    }
    
    if (!signal_unlock()){ die }
}

sub signal_lock {
    my $r;
    my $data;
    do {
        $r = sysread($signal_lock_pipefd->[0], $data, 1);
    } while (!defined $r && $! == EINTR);
    return (defined $r) ? 1 : 0;
}

sub signal_unlock {
    my $r;
    my $data = 'a';
    do {
        $r = syswrite($signal_lock_pipefd->[1], $data, 1);
    } while (!defined $r && $! == EINTR);
    return (defined $r) ? 1 : 0;
}

sub signal_handler {
    my $sig = shift;
    my $signum = $signo{$sig};
    my $saved_errno = $!;
    if (!signal_lock()) {
        $! = $saved_errno;
        return;
    }
    
    my $handle;
    for ($handle = signal_first_handle($signum);
         $handle && $handle->{signum} == $signum;
         $handle = $signal_tree->next()){
        
        $g_counter++;
        my $msg = $g_handles->{$g_counter} = {};
        $msg->{signum} = $signum;
        $msg->{handle} = $handle;
        
        my $r;
        my $wr = $g_counter . "\n";
        do {
            $r = syswrite($handle->{loop}->{signal_pipefd}->[1], $wr, length $wr);
        } while (!defined $r && $! == EINTR);
        
        assert($r == length $wr ||
           (!defined $r && ($! == EAGAIN || $! == EWOULDBLOCK)));
        
        if ($r) {
            $handle->{caught_signals}++;
        }
    }
    
    signal_unlock();
    $! = $saved_errno;
}


sub signal_start {
    my ($loop, $handle, $signal_cb, $signum) = @_;
    my $saved_sigmask;
    my $err;
    
    if (!looks_like_number($signum)) {
        $signum = $signo{uc $signum};
    }
    
    assert(!($handle->{flags} & ($CLOSING | $CLOSED)));
    
    # If the user supplies signum == 0, then return an error already. If the
    # signum is otherwise invalid then uv__signal_register will find out
    # eventually.
    
    if ($signum == 0) {
        $! = EINVAL;
        return;
    }
    
    # Short circuit: if the signal watcher is already watching {signum} don't
    # go through the process of deregistering and registering the handler.
    # Additionally, this avoids pending signals getting lost in the small time
    # time frame that handle->signum == 0.
    if ($signum == $handle->{signum}) {
        $handle->{signal_cb} = $signal_cb;
        return 1;
    }
    
    # If the signal handler was already active, stop it first. */
    if ($handle->{signum} != 0) {
        signal_stop($loop,$handle);
    }
    
    signal_block_and_lock();
    
    # If at this point there are no active signal watchers for this signum (in
    # any of the loops), it's time to try and register a handler for it here.
    
    if (!signal_first_handle($signum)) {
        if (!signal_register_handler($signum)) {
            #Registering the signal handler failed. Must be an invalid signal. */
            signal_unlock_and_unblock();
            return;
        }
    }
    
    $handle->{signum} = $signum;
    $signal_tree->insert($handle);
    
    signal_unlock_and_unblock();
    
    $handle->{signal_cb} = $signal_cb;
    $loop->handle_start($handle);
    
    return 1;
}


sub signal_block_and_lock {
    #sigset_t new_mask;
  
    #if (sigfillset(&new_mask))
    #  abort();
    #
    #if (pthread_sigmask(SIG_SETMASK, &new_mask, saved_sigmask))
    #  abort();

    if (!signal_lock()){
        die;
    }
}


sub signal_unlock_and_unblock {
    if (!signal_unlock()){
        die;
    }

    #if (pthread_sigmask(SIG_SETMASK, saved_sigmask, NULL))
    #    abort();
}


1;

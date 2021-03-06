package Rum::Loop;
use lib '../';
use strict;
use warnings;
use POSIX qw(:errno_h);
our $THREADS = 2;

use Rum::Loop::Thread;
use Rum::Loop::Pool;
use Rum::Loop::Fs;

use Time::HiRes qw(time usleep);

use Rum::Loop::Queue;
use Rum::RBTree;
use Rum::Loop::Utils 'assert';
use Rum::Loop::Core;
use Rum::Loop::Timer;
use Rum::Loop::Handle;
use Rum::Loop::Idle;
use Rum::Loop::Check;
use Rum::Loop::Prepare;
use Rum::Loop::Signal;
use Rum::Loop::IO;
use Rum::Loop::TCP;
use Rum::Loop::Stream;
use Rum::Loop::TTY;
use Rum::Loop::Process;
use Rum::Loop::Pipe;

use Rum::Loop::Flags qw(:Run :Handle :Event :IO);
use Fcntl;
use Data::Dumper;
use Carp;

use base qw/Exporter/;
our %EXPORT_TAGS = (
    CONSTANTS => [qw(
        O_RDONLY
        O_WRONLY
        O_RDWR
        RUN_DEFAULT
        RUN_ONCE
        RUN_NOWAIT
    )]
);

our @EXPORT = qw (
    O_RDONLY
    O_WRONLY
    O_RDWR
    RUN_DEFAULT
    RUN_ONCE
    RUN_NOWAIT
    default_loop
);

my $single_tone = 0;

##Globals================================================================
sub RUN_DEFAULT { $RUN_DEFAULT }
sub RUN_ONCE    { $RUN_ONCE    }
sub RUN_NOWAIT  { $RUN_NOWAIT  }

our $MAIN; # holds default_loop instance

my $QUEUE = 'Rum::Loop::Queue';
sub debug { print $_[0] . "\n" }

sub buf_init {
    my $loop = shift;
    my $str = shift;
    my $len = length $str;
    my $size = shift || $len;
    return ref $str ? $str : [$str];
    return {
        base => $str,
        len => $len,
        chunk => $size
    };
}

#========================================================================
# Request Handle
#========================================================================
sub req_register {
    my ($loop,$req) = @_;
    $req->{id} = "$req";
    $loop->{active_reqs}++;
}

sub req_unregister {
    my ($loop,$req) = @_;
    $loop->{active_reqs}--;
}

sub req_init {
    my ($loop,$req,$type) = @_;
    req_register($loop, $req);
    $req->{type} = $type;
}

#========================================================================
# Timer RB compare function
#========================================================================
sub timer_cmp {
    my ($a,$b) = @_;
    return -1 if ($a->{timeout} < $b->{timeout});
    return  1 if ($a->{timeout} > $b->{timeout});
    #compare start_id when both has the same timeout
    return -1 if ($a->{start_id} < $b->{start_id});
    return  1 if ($a->{start_id} > $b->{start_id});
    return 0;
}

sub new {
    my $class = shift;
    my $loop = bless {},$class;
    $single_tone++;
    Rum::Loop::Pool::init($loop,$THREADS);
    
    $loop->{timer_handles}   = Rum::RBTree->new(\&timer_cmp);
    $loop->{nfds}            = 0;
    $loop->{watchers}        = {};
    $loop->{nwatchers}       = 0;
    
    ##Queues==================================
    $loop->{pending_queue}   = QUEUE_INIT();
    $loop->{watcher_queue}   = QUEUE_INIT();
    
    $loop->{active_reqs}     = 0;
    ##watcher Handles=========================
    $loop->{prepare_handles} = QUEUE_INIT();
    $loop->{idle_handles}    = QUEUE_INIT();
    $loop->{check_handles}   = QUEUE_INIT();
    ##========================================
    $loop->{closing_handles} = [];
    $loop->{active_handles}  = 0;
    $loop->{backend_fd}      = -1;
    $loop->{emfile_fd}       = -1;
    $loop->{timer_counter}   = 0;
    $loop->{stop_flag}       = 0;
    $loop->{active_threads} = 0;
    $loop->{signal_pipefd} = [-1,-1];
    $loop->{process_handles} = {};
    
    update_time($loop);
    
    $loop->platform_loop_init();
    
    $loop->{child_watcher} = {};
    $loop->signal_init($loop->{child_watcher});
    $loop->handle_unref($loop->{child_watcher});
    $loop->{child_watcher}->{flags} |= $HANDLE_INTERNAL;
    
    ## set default loop ========================
    $MAIN = $loop if !$MAIN;
    return $loop;
}

sub platform_loop_init {
    my $loop = shift;
    if ($SELECT){
        $loop->{sEvents} = ['','',''];
        $loop->{children_watcher} = {};
        $loop->timer_init($loop->{children_watcher});
    } elsif ($EPOLL){
        my $fd;
        $fd = Rum::Loop::IO::EPoll::epoll_create1(1);
        if ( $fd == -1 && ($! == ENOSYS  || $! == EINVAL)) {
            $fd = Rum::Loop::IO::EPoll::epoll_create(256);
            if ( $fd > -1 ) {
                Rum::Loop::Core::cloexec($fd, 1);
            }
        }
        
        $loop->{backend_fd} = $fd;
    }
    
    
    return 1;
}

*ref          = \&handle_ref;
*unref        = \&handle_unref;
sub default_loop { $MAIN ||= __PACKAGE__->new() }
sub main_loop    { $MAIN ||= __PACKAGE__->new() }

sub loop_alive {
    my $loop = shift;
    return $loop->has_active_handles ||
        $loop->has_active_reqs ||
        $loop->{closing_handles};
}

sub has_active_reqs {
    return shift->{active_reqs} > 0;
}

sub has_active_handles {
    return shift->{active_handles} > 0;
}

sub now { shift->{time} }

sub update_time {
    shift->{time} = int( time() * 1000 );
}

sub backend_timeout {
    my $loop = shift;
    if ($loop->{stop_flag} != 0) {
        return 0;
    }
    
    if (!$loop->has_active_handles && !$loop->has_active_reqs ){
        return 0;
    }
    
    if ( !QUEUE_EMPTY($loop->{idle_handles}) ) {
        return 0;
    }
    
    if ($loop->{closing_handles}) {
        return 0;
    }
    
    ##if there is only active threads, we return a small
    ##wait value, thread work may take some time to
    ##complete and this to avoid cpu hog in the meanwhile
    if ($loop->{active_threads} > 0) {
        return 10;
    }
    
    return Rum::Loop::Timer::next_timeout($loop);
}

sub run {
    my ($loop, $mode) = @_;
    $mode ||= $RUN_DEFAULT;
    my $timeout;
    my $r = loop_alive($loop);
    loop_again : {
        while (loop_alive($loop) && $loop->{stop_flag} == 0) {
            
            $loop->update_time;
            $loop->run_timers;
            $loop->run_idle;
            $loop->run_prepare;
            $loop->run_pending;
            
            $loop->check_threads;
            
            $timeout = 0;
            if (($mode & $RUN_NOWAIT) == 0) {
                $timeout = $loop->backend_timeout;
            }
            
            $loop->io_poll($timeout);
            $loop->run_check;
            $loop->run_closing_handles;
            
            if ( $mode == $RUN_ONCE ) {
                # UV_RUN_ONCE implies forward progess: at least one callback must have
                # been invoked when it returns. uv__io_poll() can return without doing
                # I/O (meaning: no callbacks) when its timeout expires - which means we
                # have pending timers that satisfy the forward progress constraint.
                # UV_RUN_NOWAIT makes no guarantees about progress so it's omitted from
                # the check.
                
                $loop->update_time;
                $loop->run_timers;
            }
            
            if ($mode & ($RUN_ONCE | $RUN_NOWAIT)) {
                last;
            }
            
            #debug "sleeping for $timeout\n";
        }
    };
    
    ##OPTIMIZATION : don't reqister threads as active requests
    ##we already introduced a new counter {active_threads}
    ##then at the end of loop check if there is active threads
    ##and block waiting on work done then check if loop became
    ##active again ..
    while ($loop->{active_threads} > 0) {
        select undef,undef,undef,.01;
        $loop->check_threads;
        if (loop_alive($loop)) {
            goto loop_again;
        }
    }
    
    $r = $loop->loop_alive;
    
    if ($loop->{stop_flag} != 0) {
        $loop->{stop_flag} = 0;
    }
    return !$r ? 0 : 1;
}

sub check_threads {
    my $loop = shift;
    Rum::Loop::Pool::consume_work($loop);
}

sub run_pending {
    my $loop = shift;
    my $q;
    my $w;
    
    while ( !QUEUE_EMPTY($loop->{pending_queue}) ) {
        $q = QUEUE_HEAD($loop->{pending_queue});
        $w = $q->{data};
        QUEUE_REMOVE($q);
        QUEUE_INIT2($q, $w);
        $w->{cb}->($loop, $w, $POLLOUT);
    }
}

sub run_closing_handles {
    my $loop = shift;
    for (@{$loop->{closing_handles}}){
        $loop->finish_close($_);
    }
    undef $loop->{closing_handles};
}

sub finish_close {
    my $loop = shift;
    my $handle = shift;
    # Note: while the handle is in the UV_CLOSING state now, it's still possible
    # for it to be active in the sense that uv__is_active() returns true.
    # A good example is when the user calls uv_shutdown(), immediately followed
    # by uv_close(). The handle is considered active at this point because the
    # completion of the shutdown req is still pending.
    
    assert($handle->{flags} & $CLOSING, "handle already closing");
    assert(!($handle->{flags} & $CLOSED), "handle already closed");
    
    $handle->{flags} |= $CLOSED;
    
    my $type = $handle->{type};
    if ($type eq 'TIMER') {
        
    } elsif ($type eq 'IDLE') {
        
    } elsif ($type eq 'SIGNAL') {
        
    } elsif ($type eq 'PROCESS') {
        
    } elsif ($type eq 'CHECK') {
        
    } elsif ($type eq 'PREPARE') {
        
    } elsif ($type eq 'TCP' || $type eq 'NAMED_PIPE' || $type eq 'TTY') {
        $loop->stream_destroy($handle);
    } else {
        die "should never get here";
    }
    
    $loop->handle_unref($handle);
    QUEUE_REMOVE($handle->{handle_queue});
    if ($handle->{close_cb}) {
        $handle->{close_cb}->($handle);
    }
}

sub stop { shift->{stop_flag} = 1 }

sub close {
    my ($loop, $handle, $close_cb) = @_;
    croak "already closed or closing handle" if ( $handle->{flags} & ($CLOSING | $CLOSED) );
    $handle->{flags} |= $CLOSING;
    $handle->{close_cb} = $close_cb;
    
    my $type = $handle->{type};
    
    if ($type eq 'TIMER') {
        $loop->timer_close($handle);
    } elsif ($type eq 'IDLE'){
        $loop->handle_stop($handle);
    } elsif ($type eq 'CHECK'){
        $loop->check_stop($handle);
    } elsif ($type eq 'PREPARE'){
        $loop->prepare_stop($handle);
    } elsif ($type eq 'TCP'){
        $loop->tcp_close($handle);
    } elsif ($type eq 'NAMED_PIPE'){
        $loop->pipe_close($handle);
    } elsif ($type eq 'PROCESS'){
        $loop->process_close($handle);
    } elsif ($type eq 'SIGNAL'){
        $loop->signal_close($handle);
    } else {
        die "shouldn't get here";
    }
    $loop->make_close_pending($handle);
}

sub make_close_pending {
    my $loop = shift;
    my $handle = shift;
    die if !($handle->{flags} & $CLOSING);
    die if ($handle->{flags} & $CLOSED);
    push @{$loop->{closing_handles}}, $handle;
}

1;

__END__

=head1 NAME

Rum::Loop

=head1 DESCRIPTION

A Simple Event Loop Manager based on libuv

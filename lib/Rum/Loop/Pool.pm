package Rum::Loop::Pool;
use strict;
use warnings;
use Data::Dumper;

our $threads_enabled = eval "use threads; use Thread::Queue; 1";
use base qw/Exporter/;
our @EXPORT = qw (
    work_submit
);

sub Threads_enabled { $threads_enabled }
sub debug {
    #print "DEBUG : " . $_[0] . "\n";
}

my %shared : shared;
my $Handles = {};

sub init {
    my $loop = shift;
    my $threads = shift;
    if (!$threads) {
        $threads_enabled = 0;
    }
    
    if ($threads_enabled) {
        $loop->{threads_enabled} = 1;
        my %newshared : shared;
        $shared{"$loop"} = \%newshared;
        
        my $queue = $loop->{work_queue} = Thread::Queue->new();
        for (1 .. $threads){
            debug("CREATE THREAD $_ $$");
            threads->create(
                sub {
                    my $thread = threads->self();
                    my $thread_id = $thread->tid();
                    while (defined(my $req = $queue->dequeue())){
                        my $args = $req->{args};
                        $req->{thread} = $thread_id;
                        bless $req, 'Rum::Loop::Pool::THREAD';
                        debug("Got JOB at thread $thread_id");
                        do_work($req,$args);
                    }
                }
            )->detach();
        }
    }
}

{
    no strict 'refs';
    sub _no_threads_work_submit {
        my ($loop,$req,$args,$work,$callback) = @_;
        bless $req, 'Rum::Loop::Pool::THREAD';
        my $ret;
        my $error;
        eval {
            $ret = &{$work}($req,$args);
        };
        if ($@){
            $error = $@;
        }
        
        delete $req->{_notify};
        &{$callback}($error,$req,$ret);
        return 1;
    }
    
    sub work_submit {
        my ($loop,$req,$args,$work,$callback) = @_;
        if (!$loop->{threads_enabled}) {
            _no_threads_work_submit(@_);
            return;
        }
        
        my %worker;
        $req->{id} ||= "$req";
        $req->{loop_id} ||= "$loop";
        $Handles->{$req->{id}} = $req;
        
        $worker{args} = $args;
        $worker{id} = $req->{id};
        $worker{loop_id} = $req->{loop_id};
        $worker{work} = $work;
        $worker{worker} = $req->{worker};
        $worker{callback} = $callback;
        $loop->{active_threads}++;
        $loop->{work_queue}->enqueue(\%worker);
    }
    
    sub do_work {
        my $req = shift;
        my $args = shift;
        my $work = $req->{work};
        my $ret;
        eval {
            $ret = &{$work}($req, $args);
        };
        
        if ($@){
            $req->{error} = $@;
        }
        
        eval {
            delete $shared{$req->{loop_id}}{$req->{id}}->{_notify};
        };
        
        $req->{finished} = 1;
        $req->{args} = Rum::Loop::Pool::THREAD::_return_value($ret);
        $shared{$req->{loop_id}}{$req->{id}} = $req;
        undef $req;
        return 1;
    }
    
    sub consume_work {
        my $loop = shift;
        my $loop_id = "$loop";
        return if !$loop->{threads_enabled};
        for (keys %{$shared{$loop_id}}){
            my $id = $_;
            my $ret = delete $shared{$loop_id}{$id};
            next if (!$ret);
            my $req = $Handles->{$ret->{id}};
            next if (!$req);
            my $args         = delete $ret->{args};
            my $did_finish   =  delete $ret->{finished};
            my $error        =  delete $ret->{error};
            $req->{_notify}  = delete $ret->{_notify};
            my $callback = $ret->{callback};
            if ($did_finish && !$req->{_notify}) {
                delete $Handles->{$ret->{id}};
                $req->{loop}->{active_threads}--;
            }
            
            if (!$did_finish && !$req->{_notify} ) {
                next;
            }
            
            &{$callback}($error,$req,$args);
        }
    }
}

package Rum::Loop::Pool::THREAD; {
    use strict;
    use warnings;
    use Data::Dumper;
    sub notify {
        my $req = shift;
        my $val = shift;
        ##if this doesn't come from a thread
        ##invoke notify callback immediately
        if ($req->{loop} && ref $req->{loop}) {
            my $notify = $req->{notify};
            if (ref $notify eq 'CODE') {
                $notify->($req,$val);
            }
        } else {
            eval {
                $req->{_notify} = _return_value($val);
                $shared{$req->{loop_id}}{$req->{id}} = $req;
            };
        }
        return 1;
    }
    
    sub _return_value {
        my $val = shift;
        if (ref $val eq "HASH") {
            my %shared :shared;
            %shared = %{$val};
            return \%shared;
        } elsif (ref $val eq "ARRAY") {
            my @shared :shared;
            @shared = @{$val};
            return \@shared;
        } else {
            return $val;
        }
    }
}

1;

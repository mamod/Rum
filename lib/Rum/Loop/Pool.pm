package Rum::Loop::Pool;
use strict;
use warnings;

use lib '../../';
use Rum::Loop::Core;
#use threads;
#use threads::shared;
use Data::Dumper;

use Socket qw(AF_UNIX PF_UNSPEC PF_INET SOCK_STREAM);

use base qw/Exporter/;
our @EXPORT = qw (
    work_submit
);


our ($child,$parent);
my $bits = "";
#{
#    socketpair($child, $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
#    || die "socketpair: $!";
#    vec($bits, fileno $parent, 1) = 1;
#    Rum::Loop::Core::nonblock($child, 1);
#    Rum::Loop::Core::nonblock($parent, 1);
#    
#    #$child->blocking(0);
#    #$parent->blocking(0);
#    #$child->autoflush(1);
#    #$parent->autoflush(1);
#}

## ====== for return values
my %shared :shared;
my @pool : shared;
my $Handles = {};
my @threads;


our $THREADS = 2;
for (0..$THREADS){
    #push @threads, createThread();
}

sub send_thread_signal {
    my $sig = shift;
    my $index = shift;
    
    if (defined $index){
        $threads[$index]->kill($sig);
        return;
    }
    
    for (@threads){
        $_->kill($sig);
    }
}

sub createThread {
    my $thr = threads->create(
        sub {
            my $run = 1;
            $SIG{ALRM} = sub { 
                print threads->self->tid(), " got SIGALRM. Good bye.\n";
            };
            
            $SIG{STOP} = sub {
                $run = 0;
            };
            
            my $thread_id = threads->self->tid();
            
            
            ##first loop, this will be intrurrupted after
            ##creating all threads then close parent end socketpair
            while ($run){
                select undef,undef,undef,.001;
            }
            
            close $child;
            $run = 1;
            
            while ( $run ) {
                my $n = select $bits,undef,undef,undef;
                next if $n != 1;
                sysread $parent, my $buf, 1;
                
                my $req = do {
                    lock(@pool);
                    shift @pool;
                };
                next if !$req;
                eval {
                   do_work($req);
                };
                warn $@ if $@;
            }
        }
    );
    return $thr;
}

sub work_submit {
    my ($loop,$req,$work,$done) = @_;
    my %worker : shared;
    $Handles->{$req->{id}} = $req;
    for (keys %{$req}){
        next if ref $req->{$_};
        $worker{$_} = $req->{$_};
    }
    
    $worker{work} = $work;
    $worker{done} = $done;
    push @pool, \%worker;
    $child->syswrite("1");
    #send_thread_signal('ALRM');
}

{
    no strict 'refs';
    sub Consume {
        for (keys %shared){
            my $id = $_;
            my $ret = delete $shared{$id};
            my $req = delete $Handles->{$id};
            next if (!$req || !$ret);
            
            $req->{thread} = $ret->{thread};
            $req->{result} = $ret->{result};
            $req->{buf} = $ret->{buf};
            my $done = $ret->{done};
            &{$done}($req);
        }
    }
    
    sub do_work {
        my $req = shift;
        my $work = $req->{work};
        &{$work}($req);
        $shared{$req->{id}} = $req;
        #$parent->syswrite("1");
        undef $req;
    }
}

sub Close {
    for (@threads){
        $_->kill('STOP');
        eval "\$_->detach()";
    }
}

sub DESTROY {
    Close();
}

1;

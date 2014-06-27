package Rum::Loop::Pool;
use strict;
use warnings;
use threads;
use Thread::Queue;
use threads::shared;
use Data::Dumper;

## ====== for return values
my %hash :shared;
my $Handles = {};

use base qw/Exporter/;
our @EXPORT = qw (
    work_submit
);

sub do_work {
    my $req = shift;
    my $work = $$req->{work};
    no strict 'refs';
    &{$work}($$req);
    $hash{$$req->{id}} = $$req;
    undef $req;
}

my $q = Thread::Queue->new();    # A new empty queue
my $thr = threads->create(
    sub {
        # Thread will loop until no more work
        while (defined(my $req = $q->dequeue)) {
            print "this\n";
            eval {
                do_work($req);
            };
            ##what to do on errors?
        }
    }
);

my $thr2 = threads->create(
    sub {
        # Thread will loop until no more work
        while (defined(my $req = $q->dequeue)) {
            print "that\n";
            eval {
                do_work($req);
            };
            ##what to do on errors?
        }
    }
);

sub work_submit {
    my ($loop,$req,$work,$done) = @_;
    
    my $worker = {};
    $Handles->{$req->{id}} = $req;
    for (keys %{$req}){
        next if ref $req->{$_};
        $worker->{$_} = $req->{$_};
    }
    
    $worker->{work} = $work;
    $worker->{done} = $done;
    $q->enqueue(\$worker);
}

sub Consume {
    for (keys %hash){
        my $id = $_;
        my $ret = delete $hash{$id};
        my $req = delete $Handles->{$id};
        $req->{result} = $ret->{result};
        $req->{buf} = $ret->{buf};
        my $done = $ret->{done};
        no strict 'refs';
        &{$done}($req);
        undef $ret;
        ##should we keep this running or run once on every tick?
        last;
    }
}

sub Close {
    $q->end();
    $thr->join();
    $thr2->join();
}

1;

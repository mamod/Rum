package Rum::Loop::Thread;
use strict;
use warnings;
use Data::Dumper;
use Rum::Path;

use base qw/Exporter/;
our @EXPORT = qw (
    queue_work
);

my $modules = {};
sub thread_work {
    my $req = shift;
    my $args = shift;
    my $work = $req->{id};
    my $worker = $req->{worker};
    my $file = Rum::Path->resolve($worker);
    if (my $module = $modules->{$file}) {
        $module->($req,$args);
    } else {
        my $t = require $file;
        if (ref $t ne "CODE") {
            die "Worker $file - must return a code ref";
        }
        
        $modules->{$file} = $t;
        $t->($req,$args);
    }
}

sub thread_callback {
    my $err = shift;
    my $req = shift;
    my $args = shift;
    my $notify = delete $req->{_notify};
    if (!$notify) {
        $req->{callback}->($err,$req, $args);
    } else {
        $req->{notify}->($req, $notify);
    }
    return;
}

sub queue_work {
    my ($loop, $req, $options) = @_;
    $req->{id}         ||= "$req"; 
    $req->{loop}       ||= $loop;
    $req->{worker}     ||= $options->{worker};
    $req->{callback}   ||= $options->{callback};
    $req->{notify}     ||= $options->{notify};
    my $args = $options->{args};
    
    $loop->work_submit($req, $args, 'Rum::Loop::Thread::thread_work'
                            , 'Rum::Loop::Thread::thread_callback');
    return 1;
}

1;

package Rum::Loop::Queue;
use strict;
use warnings;
use Data::Dumper;

use base qw/Exporter/;
our @EXPORT = qw (
    QUEUE_INIT
    QUEUE_INIT2
    QUEUE_ADD
    QUEUE_REMOVE
    QUEUE_HEAD
    QUEUE_INSERT_TAIL
    QUEUE_INSERT_HEAD
    QUEUE_DATA
    QUEUE_EMPTY
    QUEUE_FOREACH
);

sub QUEUE_INIT {
    #my $data = shift;
    my $self = {};
    $self->{next} = $self;
    $self->{prev} = $self;
    $self->{data} = $_[0];
    return $self;
}

sub QUEUE_INIT2 {
    $_[0]->{next} = $_[0];
    $_[0]->{prev} = $_[0];
    $_[0]->{data} = $_[1];
    return 1;
}

sub QUEUE_ADD {
    
}

sub QUEUE_REMOVE {
    my $x = shift;
    $x->{next}->{prev} = $x->{prev};
    $x->{prev}->{next} = $x->{next};
    #delete $x->{prev};
    #delete $x->{next};
    undef $x->{data};
    #undef $_[0];
}

sub QUEUE_HEAD {
    shift->{next};
}

sub QUEUE_INSERT_HEAD {
    my $h = shift;
    my $x = shift;
    $x->{next} = $h->{next};
    $x->{next}->{prev} = $x;
    $x->{prev} = $h;
    $h->{next} = $x;
}

sub QUEUE_INSERT_TAIL {
    my $h = shift;
    my $x = shift;
    $x->{prev} = $h->{prev};
    $x->{prev}->{next} = $x;
    $x->{next} = $h; 
    $h->{prev} = $x;
}

sub QUEUE_EMPTY {
    my $h = shift;
    return $h == $h->{prev};
}

sub QUEUE_FOREACH {
    my $self = shift;
    my $cb = shift;
    for (my $q = QUEUE_HEAD($self); $q && $q ne $self && !QUEUE_EMPTY($self); $q = $q->{next}) {
        local $_ = $q;
        $cb->($q);
    }
}

1;

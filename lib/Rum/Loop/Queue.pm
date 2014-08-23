package Rum::Loop::Queue;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util 'weaken';
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
    QUEUE_TAIL
);

sub QUEUE_INIT {
    my $data = shift;
    my $self = {};
    $self->{next} = $self;
    $self->{prev} = $self;
    $self->{data} = $data;
    return $self;
}

sub QUEUE_INIT2 {
    my $q = shift;
    my $data = shift;
    $q->{next} = $q;
    $q->{prev} = $q;
    $q->{data} = $data;
    weaken $q->{data};
    weaken $q->{prev};
    weaken $q->{next};
}

sub QUEUE_REMOVE {
    my $x = shift;
    $x->{next}->{prev} = $x->{prev};
    $x->{prev}->{next} = $x->{next};
    undef $x->{data};
}

sub QUEUE_HEAD {
    shift->{next};
}

sub QUEUE_TAIL {
    shift->{prev};
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

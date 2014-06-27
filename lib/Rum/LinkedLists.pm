package Rum::LinkedLists;
use strict;
use warnings;
sub new {
    bless {}, shift; 
}

sub init {
    my ($self,$list) = @_;
    $list->{_idleNext} = $list;
    $list->{_idlePrev} = $list;
}

sub append {
    my ($self,$list, $item) = @_;
    $self->remove($item);
    $item->{_idleNext} = $list->{_idleNext};
    $list->{_idleNext}->{_idlePrev} = $item;
    $item->{_idlePrev} = $list;
    $list->{_idleNext} = $item;
}

#remove the most idle item from the list
sub shift  {
    my ($self,$list) = @_;
    my $first = $list->{_idlePrev};
    $self->remove($first);
    return $first;
}

sub remove {
    my ($self,$item) = @_;
    if ($item->{_idleNext}) {
        $item->{_idleNext}->{_idlePrev} = $item->{_idlePrev};
    }
    if ($item->{_idlePrev}) {
        $item->{_idlePrev}->{_idleNext} = $item->{_idleNext};
    }
    $item->{_idleNext} = undef;
    $item->{_idlePrev} = undef;
}

sub isEmpty {
    my ($self,$list) = @_;
    return $list == $list->{_idleNext};
}

sub peek {
    my ($self,$list) = @_;
    return undef if $list->{_idlePrev} && $list->{_idlePrev} == $list;
    return $list->{_idlePrev};
}

1;

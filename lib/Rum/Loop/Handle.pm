package Rum::Loop::Handle;
use strict;
use warnings;
use Rum::Loop::Queue;
use Rum::Loop::Flags qw($CLOSING $CLOSED :Handle);
use Data::Dumper;

use base qw/Exporter/;
our @EXPORT = qw (
    handle_init
    handle_ref
    handle_unref
    has_ref
    is_active
    is_closing
    handle_start
    handle_stop
    active_handle_add
    active_handle_rm
);

sub handle_init {
    my ($loop,$handle,$type) = @_;
    $_[1]->{type} = $type;
    $_[1]->{flags} = $HANDLE_REF;
    return 1;
}

sub handle_ref {
    my $loop = shift;
    my $h = shift;
    return if (($h->{flags} & $HANDLE_REF) != 0);
    $h->{flags} |= $HANDLE_REF;
    return if (($h->{flags} & $HANDLE_CLOSING) != 0);
    active_handle_add($loop) if (($h->{flags} & $HANDLE_ACTIVE) != 0);
}

sub handle_unref {
    my $loop = shift;
    my $h = shift;
    return if (($h->{flags} & $HANDLE_REF) == 0);
    $h->{flags} &= ~$HANDLE_REF;
    return if (($h->{flags} & $HANDLE_CLOSING) != 0);
    active_handle_rm($loop) if (($h->{flags} & $HANDLE_ACTIVE) != 0);
}

sub has_ref {
    my $h = shift;
    return (($h->{flags} & $HANDLE_REF) != 0);
}

sub is_active {
    my $h = shift;
    return ($h->{flags} & $HANDLE_ACTIVE) != 0;
}

sub is_closing {
    my $h = shift;
    my $flag = $h->{flags} ? $h->{flags} : 0;
    return (($flag & ($CLOSING |  $CLOSED)) != 0);
}

sub handle_start {
    my $loop = shift;
    my $h = shift;
    die if ($h->{flags} & $HANDLE_CLOSING) != 0;
    return if (($h->{flags} & $HANDLE_ACTIVE) != 0);
    $h->{flags} |= $HANDLE_ACTIVE;
    active_handle_add($loop) if (($h->{flags} & $HANDLE_REF) != 0);
}

sub handle_stop {
    my $loop = shift;
    my $h = shift;
    return if (($h->{flags} & $HANDLE_ACTIVE) == 0);
    $h->{flags} &= ~$HANDLE_ACTIVE;  
    active_handle_rm($loop) if (($h->{flags} & $HANDLE_REF) != 0);
}

sub active_handle_add {
    my $loop = shift;
    $loop->{active_handles}++;
}

sub active_handle_rm {
    my $loop = shift;
    $loop->{active_handles}--;
}

1;

package Rum::Loop::Utils;
use warnings;
use strict;
use Carp;
use base qw/Exporter/;
our @EXPORT = qw (
    assert
);

sub assert {
    my ($a,$msg) = @_;
    if (!$a) {
        Carp::croak $msg || "Assertion Error";
    }
}

1;

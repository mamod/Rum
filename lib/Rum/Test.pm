package Rum::Test;
use strict;
use warnings;
use base 'Rum::Assert';
use Rum::TryCatch;
use Data::Dumper;
my $EXIT = 0;
{
    binmode STDERR, ":utf8";
    sub fail {
        my $self = shift;
        ++$EXIT;
        my $message = _getMessage(@_);
        print STDERR "Failed: ... " . $message . "\n";
    }
}

sub _getMessage {
    my ($actual, $expected, $message, $operator) = @_;
    if ($message) {
        return $message;
    }
    
    my $msg .= '';
    $msg .= $actual . ' ' if defined $actual;
    $msg .= $operator ? $operator . ' ' : ' ';
    $msg .= $expected . ' ' if defined $expected;
    return $msg;
}

sub BEGIN {
    
}

sub END {
    
}

1;

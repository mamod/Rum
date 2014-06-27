package Rum::TryCatch;
use strict;
use warnings;
use Carp;
use Data::Dumper;
$Carp::Internal{+__PACKAGE__}++;
use base 'Exporter';
our @EXPORT = our @EXPORT_OK = qw(try catch finally);

my $finally;
my $catch;

sub try(&;@) {
    my $wantarray =  wantarray;
    ##copy then reset
    #reset blocks and counter
    my $catch_code = $catch;
    my $finally_code = $finally;
    $finally = undef;
    $catch = undef;
    my $code = shift;
    my @ret;
    my $prev_error = $@;
    
    my $fail = not eval {
        $@ = $prev_error;
        if (!defined $wantarray) {
            $code->();
        } elsif (!$wantarray) {
            $ret[0] = $code->();
        } else {
            @ret = $code->();
        }
        
        return 1;
    };
    
    my @args = $fail ? ($@) : ();
    $@ = $prev_error;
    
    if ($fail) {
        if ($catch_code) {
            local $_ = $args[0];
            for ($_){
                if (!defined $wantarray) {
                    $catch_code->(@args);
                } elsif (!$wantarray) {
                    $ret[0] = $catch_code->(@args);
                } else {
                    @ret = $catch_code->(@args);
                }
                last; ## seems to boost speed by 7%
            }
        }
    }
    
    $finally_code->(@args) if $finally_code;
    return $wantarray ? @ret : $ret[0];
}

sub catch(&;@) {
    croak 'Useless bare catch()' unless wantarray;
    croak 'One catch block allowed' if $catch;
    croak 'Missing semicolon after catch block' if $_[1];
    $catch = $_[0];
    return;
}

sub finally(&;@) {
    croak 'Useless bare finally()' unless wantarray;
    croak 'One finally block allowed' if $finally;
    croak 'Missing semicolon after finally block ' if $_[1];
    $finally = $_[0];
    return;
}

1;

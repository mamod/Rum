package Rum::Error;
use strict;
use warnings;
use Carp;
use Data::Dumper;
$Carp::Internal{+__PACKAGE__}++;
sub new {
    my ($class,$message) = @_;
    bless {
        caller => caller,
        message => $message
    }, $class;
}

sub throw {
    my $self = shift;
    my $message = '';
    $message .= $self->{name} . ': ' if  $self->{name};
    $message .= $self->{message} || '';
    my $stack = 10;
    my $caller = [];
    my @stack;
    my $found = 0;
    
    while (--$stack > 0){
        my @callers = caller($stack);
        push @stack, \@callers;
    }
    
    if (ref $self eq 'Rum::Error') {
        my @trace;
        $caller = [caller(0)];
        foreach my $stack (reverse @stack){
            next if (!$stack->[0] || !$stack->[1]);
            next if $stack->[0] =~ (/Rum::TryCatch|main/);
            push @trace, "\t at: " .
                ($stack->[0] =~ /Rum::SandBox/ ? $stack->[1] : $stack->[0]) .
                ":" .
                $stack->[2];
        }
        
        my $message = [
            'Died => ' . $caller->[1] . ':' . $caller->[2],
            'Error: ' . $message,
            '',
            'Stack Trace',
            '==================================',
            '',
            @trace
        ];
        die join("\n" , @{$message}) . "\n";
    }
    
    $caller = [caller(2)];
    die $message . " at " . $caller->[1] . " line " . $caller->[2] . "\n";
}

1;

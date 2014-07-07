package Rum::Domain;
use strict;
use warnings;
use Data::Dumper;
use base 'Rum::EventEmitter';
use Rum;

$Rum::EventEmitter::usingDomain = 1;

Rum::module()->{exports} = 'Rum::Domain'; 

my $_domain_flag = {};
my $_domain = [undef];
my @stack = ();

#the active domain is always the one that we're currently in.
my $active = 0;

sub Rum::Process::domain {
    my $self = shift;
    if (@_) {
        $_domain->[0] = @_;
    }
    return $_domain->[0];
}

sub create {
    return Rum::Domain::new();
}

sub new {
    bless {
        members => []
    }, __PACKAGE__;
}

sub add {
    my ($this,$ee) = @_;
    #disposed domains can't be used for new things.
    return if ( $this->{_disposed} );
    
    #already added to this domain.
    return if ($ee->{domain} && $ee->{domain} == $this);
    
    #has a domain already - remove it first.
    if ( $ee->{domain} ) {
        $ee->{domain}->remove($ee);
    }
    
    #// check for circular Domain->Domain links.
    #// This causes bad insanity!
    #//
    #// For example:
    #// var d = domain.create();
    #// var e = domain.create();
    #// d.add(e);
    #// e.add(d);
    #// e.emit('error', er); // RangeError, stack overflow!
    if ($this->{domain} && (ref $ee eq 'Rum::Domain')) {
        while (my $d = $this->{domain}) {
            return if ($ee == $d);
            $d = $d->{domain};
        }
    }
    
    $ee->{domain} = $this;
    push @{$this->{members}}, $ee;
}

sub enter {
    my $this = shift;
    return if ($this->{_disposed});
    
    #note that this might be a no-op, but we still need
    #to push it onto the stack so that we can pop it later.
    $active = process->domain($this);
    push @stack, $this;
    $_domain_flag->{0} = scalar @stack;
}

sub exit {
    my $this = shift;
    return if ($this->{_disposed});
    
    #exit all domains until this one.
    my $d;
    do {
        $d = pop @stack;
    } while ($d && $d != $this);
    
    my $length = scalar @stack;
    $_domain_flag->{0} = $length;
    $active = $stack[$length - 1];
    process->domain($active);
}

1;

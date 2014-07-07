package Rum::FreeList;
use strict;
use warnings;

sub new {
    my ($class, $name, $max, $constructor) = @_;
    my $this = bless({}, $class);
    $this->{name} = $name;
    $this->{constructor} = $constructor;
    $this->{max} = $max;
    $this->{list} = [];
}

sub alloc {
    my $this = shift;
    #debug("alloc " + this.name + " " + this.list.length);
    return @{$this->{list}} ? shift @{$this->{list}} :
                            $this->{constructor}->($this, @_);
}

sub free {
    my ($this,$obj) = @_;
    #debug("free " + this.name + " " + this.list.length);
    if (@{$this->{list}} < $this->{max}) {
        push @{$this->{list}}, $obj;
    }
}

1;

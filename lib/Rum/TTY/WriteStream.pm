package Rum::TTY::WriteStream;
use strict;
use warnings;
use Data::Dumper;
use Rum::Wrap::TTY;
use base 'Rum::Net::Socket';

sub new {
    my ($class, $fh) = @_;
    
    my $this = bless {}, $class;
    Rum::Net::Socket::new($this, {
        handle => Rum::Wrap::TTY->new($fh, 0),
        readable => 0,
        writable => 1
    });
    
    return $this;
}

sub isTTY { 1 }


1;

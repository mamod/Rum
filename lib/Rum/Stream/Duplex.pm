package Rum::Stream::Duplex;
use lib '../../';
use Rum::Utils;
use Rum::Error;
use Rum::Buffer;
use warnings;
use strict;
use base qw/Rum::Stream::Readable Rum::Stream::Writable/;

my $util = 'Rum::Utils';
use Data::Dumper;

sub write { &Rum::Stream::Writable::write }
sub end { &Rum::Stream::Writable::end }

sub new {
    my ($class,$options) = @_;
    my $this = ref $class ? $class : bless {}, $class;
    
    Rum::Stream::Readable::new($this, $options);
    Rum::Stream::Writable::new($this, $options);
    
    if ($options && defined $options->{readable}) {
        $this->{readable} = $options->{readable};
    }
    
    if ($options && defined $options->{writable}) {
        $this->{writable} = $options->{writable};
    }

    $this->{allowHalfOpen} = 1;
    
    if ($options && defined $options->{allowHalfOpen}) {
        $this->{allowHalfOpen} = $options->{allowHalfOpen};
    }
    
    $this->once('end', \&onend);
    
    return $this;
}

sub onend {
    my $this = shift;
    my @args = @_;
    #if we allow half-open state, or if the writable side ended,
    #then we're ok.
    if ($this->{allowHalfOpen} || $this->{_writableState}->{ended} ) {
        return;
    }
    
    #no more data can be written.
    #But allow more writes to happen in this tick.
    Rum::Process->nextTick(sub {
        $this->end();
    });
}

1;

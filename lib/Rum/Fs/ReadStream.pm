package Rum::Fs::ReadStream;
use Rum;
use Rum::Utils;
use Rum::Buffer;
use base 'Rum::Stream::Readable';
my $util = 'Rum::Utils';
my $fs = 'Rum::Fs';

my $kMinPoolSpace = 128;
my $pool = undef;

sub new {
    my ($class, $path, $options) = @_;
    
    my $this = bless {}, $class;
    #if (!(this instanceof ReadStream))
    #  return new ReadStream(path, options);

    #a little bit bigger buffer and water marks by default
    $options->{highWaterMark} ||= 64 * 1024;
    
    $this->SUPER::new($options);

    $this->{path} = $path;
    $this->{fd} = $options->{fd};
    $this->{flags} = $options->{flags} ? $options->{flags} : 'r';
    $this->{mode} = $options->{mode} ? $options->{flags} : 438; #=0666

    my $start = $this->{start} = $options->{start};
    my $end = $this->{end} = $options->{end};
    $this->{autoClose} = defined $options->{autoClose} ? $options->{autoClose} : 1;
    $this->{pos} = undef;
    
    if ( !$util->isUndefined( $start ) ) {
        if (!$util->isNumber($start) ) {
            Carp::croak('start must be a Number');
        }
        if ( $util->isUndefined($end) ) {
            ##FIXME : this should be an infinite value
            ## but setting this to infinite thows an error
            ## on Rum::Fs _read
            $end = $this->{end} = $options->{highWaterMark}-2;
            #$end = $this->{end} = 'Infinity';
        } elsif (!$util->isNumber($end)) {
            Carp::croak('end must be a Number');
        }
        
        if ($start > $end) {
            Carp::croak('start must be <= end');
        }
        
        $this->{pos} = $this->{start};
    }

    if ( !$util->isNumber( $this->{fd} )) {
        $this->open();
    }
    
    $this->on('end', sub {
        if ( $this->{autoClose} ) {
            $this->destroy();
        }
    });
    
    return $this;
}

sub open {
    my $this = shift;
    $fs->open($this->{path}, $this->{flags}, $this->{mode}, sub {
        my ($er, $fd) = @_;
        if ($er) {
            if ( $this->{autoClose} ) {
                $this->destroy();
            }
            $this->emit('error', $er);
            return;
        }
        
        $this->{fd} = $fd;
        $this->emit('open', $fd);
        #start the flow of data.
        $this->read();
    });
}

sub _read  {
    my ($this,$n) = @_;
    if (!$util->isNumber( $this->{fd} )) {
        return $this->once('open', sub {
            $this->_read($n);
        });
    }
    
    return if ($this->{destroyed});

    if (!$pool || $pool->length - $pool->{used} < $kMinPoolSpace) {
        #discard the old pool.
        $pool = undef;
        allocNewPool( $this->{_readableState}->{highWaterMark} );
    }

    #Grab another reference to the pool in the case that while we're
    #in the thread pool another read() finishes up the pool, and
    #allocates a new one.
    my $thisPool = $pool;
    my $toRead = $util->min($pool->length - $pool->{used}, $n);
    my $start = $pool->{used};

    if (defined $this->{pos}) {
        $toRead = $util->min($this->{end} - $this->{pos} + 1, $toRead);
    }
    #already read everything we were supposed to read!
    #treat as EOF.
    if ($toRead <= 0){
        return $this->push(undef);
    }
    
    my $self = $this;
    my $onread = sub {
        my ($er, $bytesRead) = @_;
        if ($er) {
            if ($self->{autoClose}) {
                $self->destroy();
            }
            $self->emit('error', $er);
        } else {
            my $b = undef;
            if ($bytesRead > 0) {
                $b = $thisPool->slice($start, $start + $bytesRead);
            }
            $self->push($b);
        }
    };
    #the actual read.
    $fs->read($this->{fd}, $pool, $pool->{used}, $toRead, $this->{pos}, $onread);
    
    #move the pool positions, and internal position for reading.
    if ( defined $this->{pos} ){
        $this->{pos} += $toRead;
    }
    
    $pool->{used} += $toRead;
    
}

sub destroy {
    my $this = shift;
    return if ($this->{destroyed});
    $this->{destroyed} = 1;

    if ($util->isNumber( $this->{fd} )){
        $this->close();
    }
}

sub close {
    my ($this,$cb) = @_;
    $this->once('close', $cb) if ($cb);
    
    my $close = sub {
        my ($self,$fd) = @_;
        $fs->close($fd || $self->{fd}, sub {
            my ($er) = @_;
            if ($er) {
                $self->emit('error', $er);
            } else {
                $self->emit('close');
            }
        });
        
        $self->{fd} = undef;
    };
    
    if ($this->{closed} || !$util->isNumber($this->{fd})) {
        if (!$util->isNumber($this->{fd})) {
            $this->once('open', $close);
            return;
        }
        return process->nextTick( sub {
            $this->emit('close');
        });
    }
    
    $this->{closed} = 1;
    $close->($this);
}

sub allocNewPool {
    my ($poolSize) = @_;
    $pool = Rum::Buffer->new($poolSize);
    $pool->{used} = 0;
}

1;

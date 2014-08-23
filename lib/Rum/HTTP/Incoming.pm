package Rum::HTTP::Incoming;
use strict;
use warnings;
use Scalar::Util 'weaken';
use Rum 'module';
use base 'Rum::Stream::Readable';

my $util = 'Rum::Utils';

sub readStart {
    my $socket = shift;
    if ($socket && !$socket->{_paused} && $socket->{readable}) {
        $socket->resume();
    }
}

sub readStop {
    my $socket = shift;
    if ($socket) {
        $socket->pause();
    }
}

module->{exports} = {
    readStart => \&readStart,
    readStop => \&readStop,
    IncomingMessage => 'Rum::HTTP::Incoming'
};

# Abstract base class for ServerRequest and ClientResponse. */
sub new {
    my $class = shift;
    my $socket = shift;
    my $this = bless({}, $class);
    
    Rum::Stream::Readable::new($this);
    
    # XXX This implementation is kind of all over the place
    # When the parser emits body chunks, they go in this list.
    # _read() pulls them out, and when it finds EOF, it ends.
    
    weaken($this->{socket} = $socket);
    weaken($this->{connection} = $socket);
    
    $this->{httpVersion} = undef;
    $this->{complete} = 0;
    $this->{headers} = {};
    $this->{rawHeaders} = [];
    $this->{trailers} = {};
    $this->{rawTrailers} = [];
    
    $this->{readable} = 1;
    
    $this->{_pendings} = [];
    $this->{_pendingIndex} = 0;
    
    # request (server) only
    $this->{url} = '';
    $this->{method} = undef;
    
    # response (client) only
    $this->{statusCode} = undef;
    $this->{statusMessage} = undef;
    weaken($this->{client} = $this->{socket});
    
    #flag for backwards compatibility grossness.
    $this->{_consuming} = 0;
    
    #flag for when we decide that this message cannot possibly be
    #read by the user, so there's no point continuing to handle it.
    $this->{_dumped} = 0;
    return $this;
}

sub setTimeout {
    my ($this, $msecs, $callback) = @_;
    if ($callback){
        $this->on('timeout', $callback);
    }
    
    $this->{socket}->setTimeout($msecs);
}

sub read {
    my ($this, $n) = @_;
    $this->{_consuming} = 1;
    $this->{read} = \&Rum::Stream::Readable::read;
    return $this->{read}->($this, $n);
}

sub _read {
    my ($this, $n) = @_;
    #We actually do almost nothing here, because the parserOnBody
    #function fills up our internal buffer directly. However, we
    #do need to unpause the underlying socket so that it flows.
    if ($this->{socket}->{readable}) {
        readStart($this->{socket});
    }
}

#It's possible that the socket will be destroyed, and removed from
#any messages, before ever calling this. In that case, just skip
#it, since something else is destroying this connection anyway.
sub destroy {
    my ($this, $error) = @_;
    if ($this->{socket}) {
        $this->{socket}->destroy($error);
    }
}

sub _addHeaderLines {
    my ($this, $headers, $n) = @_;
    if ($headers && scalar @{$headers}) {
        my ($raw, $dest);
        if ($this->{complete}) {
            $raw = $this->{rawTrailers};
            $dest = $this->{trailers};
        } else {
            $raw = $this->{rawHeaders};
            $dest = $this->{headers};
        }
        
        #raw.push.apply(raw, headers);
        
        for (my $i = 0; $i < $n; $i += 2) {
            my $k = $headers->[$i];
            my $v = $headers->[$i + 1];
            $this->_addHeaderLine($k, $v, $dest);
        }
    }
}

#Add the given (field, value) pair to the message

#Per RFC2616, section 4.2 it is acceptable to join multiple instances of the
#same header with a ', ' if the header in question supports specification of
#multiple values this way. If not, we declare the first instance the winner
#and drop the second. Extended header fields (those beginning with 'x-') are
#always joined.

sub _addHeaderLine {
    my ($this, $field, $value, $dest) = @_;
    $field = lc $field;
    
    if ($field eq 'set-cookie') {
        if (ref $dest->{$field} eq 'ARRAY') {
            push @{$dest->{$field}}, $value;
        } else {
            $dest->{$field} = [$value];
        }
    } elsif (   $field eq 'content-type'
             || $field eq 'content-length'
             || $field eq 'user-agent'
             || $field eq 'referer'
             || $field eq 'host'
             || $field eq 'authorization'
             || $field eq 'proxy-authorization'
             || $field eq 'if-modified-since'
             || $field eq 'if-unmodified-since'
             || $field eq 'from'
             || $field eq 'location'
             || $field eq 'max-forwards'){
        
        #drop duplicates
        if (!$dest->{$field}){
            $dest->{$field} = $value;
        }
    } else {
        # make comma-separated list
        if ( $dest->{$field} ) {
            $dest->{$field} .= ', ' . $value;
        } else {
            $dest->{$field} = $value;
        }
    }
}

#Call this instead of resume() if we want to just
#dump all the data to /dev/null
sub _dump {
    my $this = shift;
    if (!$this->{_dumped}) {
        $this->{_dumped} = 1;
        $this->resume();
    }
}

1;

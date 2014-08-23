package Rum::HTTP::Outgoing;
use strict;
use warnings;
use Scalar::Util 'weaken';
use Rum::Loop::Utils 'assert';
use base 'Rum::Stream';
use Rum::HTTP::Common;
use Rum 'process';
use Rum::Buffer;
my $util = 'Rum::Utils';
use Data::Dumper;

my $connectionExpression = qr/Connection/i;
my $transferEncodingExpression = qr/Transfer-Encoding/i;
my $closeExpression = qr/close/i;
my $contentLengthExpression = qr/Content-Length/i;
my $dateExpression = qr/Date/i;
my $expectExpression = qr/Expect/i;
my $chunkExpression = $Rum::HTTP::Common::chunkExpression;
my $CRLF = $Rum::HTTP::Common::CRLF;

*debug = \&Rum::HTTP::Common::debug;

my $crlf_buf = Rum::Buffer->new("\r\n");

sub new {
    my $this = shift;
    
    $this = ref $this ? $this : bless {}, __PACKAGE__;  
    Rum::Stream::new($this);
    
    $this->{output} = [];
    $this->{outputEncodings} = [];
    $this->{outputCallbacks} = [];
    
    $this->{writable} = 1;
    
    $this->{_last} = 0;
    $this->{chunkedEncoding} = 0;
    $this->{shouldKeepAlive} = 1;
    $this->{useChunkedEncodingByDefault} = 1;
    $this->{sendDate} = 0;
    $this->{_removedHeader} = {};
    
    $this->{_hasBody} = 1;
    $this->{_trailer} = '';
    
    $this->{finished} = 0;
    $this->{_hangupClose} = 0;
    
    $this->{socket} = undef;
    $this->{connection} = undef;
    return $this;
}

my $automaticHeaders = {
    connection => 1,
    'content-length' => 1,
    'transfer-encoding' => 1,
    date => 1
};

sub setHeader {
    my ($this, $name, $value) = @_;
    if (@_ < 2) {
        Rum::Error->new('`name` and `value` are required for setHeader().')->throw();
    }
    
    if ($this->{_header}) {
        Rum::Error->new('Can\'t set headers after they are sent.')->throw();
    }
    
    my $key = lc $name;
    $this->{_headers} = $this->{_headers} || {};
    $this->{_headerNames} = $this->{_headerNames} || {};
    $this->{_headers}->{$key} = $value;
    $this->{_headerNames}->{$key} = $name;
    if ($automaticHeaders->{$key}) {
        $this->{_removedHeader}->{$key} = 0;
    }
}

sub getHeader {
    my ($this, $name) = @_;
    if (@_ < 1) {
        Rum::Error->new('`name` is required for getHeader().')->throw();
    }
    
    if (!$this->{_headers}) { return; }
    
    my $key = lc $name;
    return $this->{_headers}->{$key};
}

sub end {
    my ($this, $data, $encoding, $callback) = @_;
    if ($util->isFunction($data)) {
        $callback = $data;
        $data = undef;
    } elsif ($util->isFunction($encoding)) {
        $callback = $encoding;
        $encoding = undef;
    }
    
    if ($data && !$util->isString($data) && !$util->isBuffer($data)) {
        Rum::Error->new('first argument must be a string or Buffer')->throw;
    }
    
    if ($this->{finished}) {
        return 0;
    }
    
    my $self = $this;
    my $finish = sub {
        $self->emit('finish');
    };
    
    if ($util->isFunction($callback)) {
        $this->once('finish', $callback);
    }
    
    if (!$this->{_header}) {
        $this->_implicitHeader();
    }
    
    if ($data && !$this->{_hasBody}) {
        debug('This type of response MUST NOT have a body. ' .
            'Ignoring data passed to end().');
        $data = undef;
    }
    
    if ($this->{connection} && $data) {
        $this->{connection}->cork();
    }
    
    my $ret;
    if ($data) {
        # Normal body write.
        $ret = $this->write($data, $encoding);
    }
    
    if ($this->{chunkedEncoding}) {
        $ret = $this->_send("0\r\n" . $this->{_trailer} . "\r\n", 'binary', $finish);
    } else {
        #Force a flush, HACK.
        $ret = $this->_send('', 'binary', $finish);
    }
    
    if ($this->{connection} && $data) {
        $this->{connection}->uncork();
    }
    
    $this->{finished} = 1;
    
    # There is the first message on the outgoing queue, and we've sent
    # everything to the socket.
    debug('outgoing message end.');
    
    if (@{$this->{output}} == 0 && $this->{connection}->{_httpMessage} == $this) {
        $this->_finish();
    }
    
    return $ret;
}


sub _renderHeaders {
    my $this = shift;
    if ($this->{_header}) {
        die('Can\'t render headers after they are sent to the client.');
    }
    
    if (!$this->{_headers}) { return {} }
    
    my $headers = {};
    my @keys = keys %{$this->{_headers}};
    my $l = 0;
    for (my $i = 0, $l = scalar @keys; $i < $l; $i++) {
        my $key = $keys[$i];
        $headers->{$this->{_headerNames}->{$key}} = $this->{_headers}->{$key};
    }
    return $headers;
}


sub _storeHeader {
    my ($this, $firstLine, $headers) = @_;
    # firstLine in the case of request is: 'GET /index.html HTTP/1.1\r\n'
    # in the case of response it is: 'HTTP/1.1 200 OK\r\n'
    my $state = {
        sentConnectionHeader => 0,
        sentContentLengthHeader => 0,
        sentTransferEncodingHeader => 0,
        sentDateHeader => 0,
        sentExpect => 0,
        messageHeader => $firstLine
    };
    
    my ($field, $value);
    
    if ($headers) {
        my @keys = keys %{$headers};
        my $isArray = $util->isArray($headers);
        my ($field, $value);
        my $l = 0;
        for (my $i = 0, $l = scalar @keys; $i < $l; $i++) {
            my $key = $keys[$i];
            if ($isArray) {
                $field = $headers->{$key}->[0];
                $value = $headers->{$key}->[1];
            } else {
                $field = $key;
                $value = $headers->{$key};
            }
            
            if ($util->isArray($value)) {
                for (my $j = 0; $j < @{$value}; $j++) {
                    storeHeader($this, $state, $field, $value->[$j]);
                }
            } else {
                storeHeader($this, $state, $field, $value);
            }
        }
    }
    
    #Date header
    if ($this->{sendDate} && $state->{sentDateHeader} == 0) {
        $state->{messageHeader} .= 'Date: ' . utcDate() . $CRLF;
    }
    
    #Force the connection to close when the response is a 204 No Content or
    #a 304 Not Modified and the user has set a "Transfer-Encoding: chunked"
    #header.
    
    #RFC 2616 mandates that 204 and 304 responses MUST NOT have a body but
    #node.js used to send out a zero chunk anyway to accommodate clients
    #that don't have special handling for those responses.
    
    #It was pointed out that this might confuse reverse proxies to the point
    #of creating security liabilities, so suppress the zero chunk and force
    #the connection to close.
    my $statusCode = $this->{statusCode};
    if (($statusCode && ($statusCode == 204 || $statusCode == 304)) &&
        $this->{chunkedEncoding}) {
        debug($statusCode . ' response should not use chunked encoding,' .
          ' closing connection.');
        $this->{chunkedEncoding} = 0;
        $this->{shouldKeepAlive} = 0;
    }
    
    #keep-alive logic
    if ($this->{_removedHeader}->{connection}) {
        $this->{_last} = 1;
        $this->{shouldKeepAlive} = 0;
    } elsif (!$state->{sentConnectionHeader}) {
        my $shouldSendKeepAlive = $this->{shouldKeepAlive} &&
        ($state->{sentContentLengthHeader} ||
         $this->{useChunkedEncodingByDefault} ||
         $this->{agent});
        
        if ($shouldSendKeepAlive) {
            $state->{messageHeader} .= "Connection: keep-alive\r\n";
        } else {
            $this->{_last} = 1;
            $state->{messageHeader} .= "Connection: close\r\n";
        }
    }
    
    if (!$state->{sentContentLengthHeader} &&
        !$state->{sentTransferEncodingHeader}) {
        
        if ($this->{_hasBody} && !$this->{_removedHeader}->{'transfer-encoding'}) {
            if ($this->{useChunkedEncodingByDefault}) {
                $state->{messageHeader} .= "Transfer-Encoding: chunked\r\n";
                $this->{chunkedEncoding} = 1;
            } else {
                $this->{_last} = 1;
            }
        } else {
            #Make sure we don't end the 0\r\n\r\n at the end of the message.
            $this->{chunkedEncoding} = 0;
        }
    }
    
    $this->{_header} = $state->{messageHeader} . $CRLF;
    $this->{_headerSent} = 0;
    
    #wait until the first body chunk, or close(), is sent to flush,
    #UNLESS we're sending Expect: 100-continue.
    if ($state->{sentExpect}) { $this->_send('') }
}

sub storeHeader {
    my ($self, $state, $field, $value) = @_;
    #Protect against response splitting. The if statement is there to
    #minimize the performance impact in the common case.
    if ($value =~ /[\r\n]/) {
        $value =~ s/[\r\n]+[ \t]*//g;
    }
    
    $state->{messageHeader} .= $field . ': ' . $value . $CRLF;
    
    if ($field =~ $connectionExpression) {
        $state->{sentConnectionHeader} = 1;
        if ($value =~ $closeExpression) {
            $self->{_last} = 1;
        } else {
            $self->{shouldKeepAlive} = 1;
        }
        
    } elsif ($field =~ $transferEncodingExpression) {
        $state->{sentTransferEncodingHeader} = 1;
        if ($value =~ $chunkExpression) { $self->{chunkedEncoding} = 1 }
    } elsif ($field =~ $contentLengthExpression) {
        $state->{sentContentLengthHeader} = 1;
    } elsif ($field =~ $dateExpression) {
        $state->{sentDateHeader} = 1;
    } elsif ($field =~ $expectExpression) {
        $state->{sentExpect} = 1;
    }
}


#This abstract either writing directly to the socket or buffering it.
sub _send {
    my ($this, $data, $encoding, $callback) = @_;
    #This is a shameful hack to get the headers and first body chunk onto
    #the same packet. Future versions of Node are going to take care of
    #this at a lower level and in a more general way.
    $encoding ||= '';
    if (!$this->{_headerSent}) {
        if ($util->isString($data) &&
            $encoding ne 'hex' &&
            $encoding ne 'base64') {
            $data = $this->{_header} . $data;
        } else {
            unshift @{$this->{output}}, $this->{_header};
            unshift @{$this->{outputEncodings}}, 'binary';
            unshift @{$this->{outputCallbacks}}, undef;
        }
        $this->{_headerSent} = 1;
    }
    return $this->_writeRaw($data, $encoding, $callback);
}


sub _writeRaw {
    my ($this, $data, $encoding, $callback) = @_;
    if ($util->isFunction($encoding)) {
        $callback = $encoding;
        $encoding = undef;
    }
    
    if ($util->BufferOrStringLength($data) == 0) {
        if ($util->isFunction($callback)) {
            process->nextTick($callback);
        }
        return 1;
    }
    
    if ($this->{connection} &&
        $this->{connection}->{_httpMessage} == $this &&
        $this->{connection}->{writable} &&
        !$this->{connection}->{destroyed}) {
        #There might be pending data in the this.output buffer.
        while (@{$this->{output}}) {
            if (!$this->{connection}->{writable}) {
                $this->_buffer($data, $encoding, $callback);
                return 0;
            }
            my $c = shift @{$this->{output}};
            my $e = shift @{$this->{outputEncodings}};
            my $cb = shift @{$this->{outputCallbacks}};
            $this->{connection}->write($c, $e, $cb);
        }
        
        #Directly write to socket.
        return $this->{connection}->write($data, $encoding, $callback);
    } elsif ($this->{connection} && $this->{connection}->{destroyed}) {
        # The socket was destroyed. If we're still trying to write to it,
        # then we haven't gotten the 'close' event yet.
        return 0;
    } else {
        # buffer, as long as we're not destroyed.
        $this->_buffer($data, $encoding, $callback);
        return 0;
    }
}

sub _buffer {
    my ($this, $data, $encoding, $callback) = @_;
    push @{$this->{output}}, $data;
    push @{$this->{outputEncodings}}, $encoding;
    push @{$this->{outputCallbacks}}, $callback;
    weaken($this->{outputCallbacks}->[-1]);
    return 0;
}

my @MON  = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my @WDAY = qw( Sun Mon Tue Wed Thu Fri Sat );
sub utcDate {
    
    my($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime();
    $year += 1900;
    
    return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
        $WDAY[$wday], $mday, $MON[$mon], $year, $hour, $min, $sec);
    
    #if (!dateCache) {
    #    var d = new Date();
    #    dateCache = d.toUTCString();
    #    timers.enroll(utcDate, 1000 - d.getMilliseconds());
    #    timers._unrefActive(utcDate);
    #}
    #return $dateCache;
}

#This logic is probably a bit confusing. Let me explain a bit:

#In both HTTP servers and clients it is possible to queue up several
#outgoing messages. This is easiest to imagine in the case of a client.
#Take the following situation:

#req1 = client.request('GET', '/');
#req2 = client.request('POST', '/');

#When the user does

#req2.write('hello world\n');

#it's possible that the first request has not been completely flushed to
#the socket yet. Thus the outgoing messages need to be prepared to queue
#up data internally before sending it on further to the socket's queue.

#This function, outgoingFlush(), is called by both the Server and Client
#to attempt to flush any pending messages out to the socket.
sub _flush {
    my $this = shift;
    if ($this->{socket} && $this->{socket}->{writable}) {
        my $ret;
        while (@{$this->{output}}) {
            my $data = shift @{$this->{output}};
            my $encoding = shift @{$this->{outputEncodings}};
            my $cb = shift @{$this->{outputCallbacks}};
            $ret = $this->{socket}->write($data, $encoding, $cb);
        }
        
        if ($this->{finished}) {
            #This is a queue to the server or client to bring in the next this.
            $this->_finish();
        } elsif ($ret) {
            #This is necessary to prevent https from breaking
            $this->emit('drain');
        }
    }
}

sub _finish {
    my $this = shift;
    assert($this->{connection});
    $this->emit('prefinish');
}

sub write {
    my ($this, $chunk, $encoding, $callback) = @_;
    $encoding ||= '';
    if (!$this->{_header}) {
        $this->_implicitHeader();
    }
    
    if (!$this->{_hasBody}) {
        debug('This type of response MUST NOT have a body. ' .
            'Ignoring write() calls.');
        return 1;
    }
    
    if (!$util->isString($chunk) && !$util->isBuffer($chunk)) {
        Rum::Error->new('first argument must be a string or Buffer')->throw;
    }
    
    #If we get an empty string or buffer, then just do nothing, and
    #signal the user to keep writing.
    if ($util->BufferOrStringLength($chunk) == 0) { return 1 };
    
    my ($len, $ret);
    if ($this->{chunkedEncoding}) {
        if ($util->isString($chunk) &&
            $encoding ne 'hex' &&
            $encoding ne 'base64' &&
            $encoding ne 'binary') {
            
            $len = Rum::Buffer->byteLength($chunk, $encoding);
            $chunk = sprintf("%x", $len) . $CRLF . $chunk . $CRLF;
            $ret = $this->_send($chunk, $encoding, $callback);
        } else {
            # buffer, or a non-toString-friendly encoding
            if ($util->isString($chunk)) {
                $len = Rum::Buffer->byteLength($chunk, $encoding);
            } else {
                $len = $chunk->length;
            }
            
            if ($this->{connection} && !$this->{connection}->{corked}) {
                $this->{connection}->cork();
                my $conn = $this->{connection};
                process->nextTick( sub {
                    if ($conn){
                        $conn->uncork();
                    }
                });
            }
            
            $this->_send(sprintf("%x", $len), 'binary', undef);
            $this->_send($crlf_buf, undef, undef);
            $this->_send($chunk, $encoding, undef);
            $ret = $this->_send($crlf_buf, undef, $callback);
        }
    } else {
        $ret = $this->_send($chunk, $encoding, $callback);
    }
    
    debug('write ret = ' . $ret);
    return $ret;
}

sub destroy {
    my ($this, $error) = @_;
    if ($this->{socket}) {
        $this->{socket}->destroy($error);
    } else {
        $this->once('socket', sub {
            my ($this, $socket) = @_;
            $socket->destroy($error);
        });
    }
}

1;

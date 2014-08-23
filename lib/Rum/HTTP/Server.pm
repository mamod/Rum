package Rum::HTTP::Server;
use strict;
use warnings;
use Scalar::Util 'weaken';
use Rum::Loop::Utils 'assert';
use base 'Rum::Net::Server';
use Rum::HTTP::Common;
use Data::Dumper;
my $util = 'Rum::Utils';

my $HTTPParser;
my $parsers = $Rum::HTTP::Common::parsers;
my $continueExpression = $Rum::HTTP::Common::chunkExpression;
my $chunkExpression = $Rum::HTTP::Common::chunkExpression;
my $CRLF = $Rum::HTTP::Common::CRLF;
*httpSocketSetup = \&Rum::HTTP::Common::httpSocketSetup;
*freeParser = \&Rum::HTTP::Common::freeParser;
*debug = \&Rum::HTTP::Common::debug;

our %STATUS_CODES = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing', ## RFC 2518, obsoleted by RFC 4918
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status', ## RFC 4918
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Moved Temporarily',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect', ## RFC 7238
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Time-out',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Requested Range Not Satisfiable',
    417 => 'Expectation Failed',
    418 => 'I\'m a teapot', ## RFC 2324
    422 => 'Unprocessable Entity', ## RFC 4918
    423 => 'Locked', ## RFC 4918
    424 => 'Failed Dependency', ## RFC 4918
    425 => 'Unordered Collection', ## RFC 4918
    426 => 'Upgrade Required', ## RFC 2817
    428 => 'Precondition Required', ## RFC 6585
    429 => 'Too Many Requests', ## RFC 6585
    431 => 'Request Header Fields Too Large',## RFC 6585
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Time-out',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates', ## RFC 2295
    507 => 'Insufficient Storage', ## RFC 4918
    509 => 'Bandwidth Limit Exceeded',
    510 => 'Not Extended', ## RFC 2774
    511 => 'Network Authentication Required' ## RFC 6585
);

sub new {
    my ($class, $requestListener) = @_;
    my $this = ref $class ? $class : bless({}, $class);
    Rum::Net::Server::new($this, { allowHalfOpen => 1 });
    
    if ($requestListener) {
        $this->addListener('request', $requestListener);
    }
    
    #Similar option to this. Too lazy to write my own docs.
    #http://www.squid-cache.org/Doc/config/half_closed_clients/
    #http://wiki.squid-cache.org/SquidFaq/InnerWorkings#What_is_a_half-closed_filedescriptor.3F
    $this->{httpAllowHalfOpen} = 0;
    
    $this->addListener('connection', \&connectionListener);
    
    $this->addListener('clientError', sub {
        my ($this, $err, $conn) = @_;
        $conn->destroy($err);
    });
    
    $this->{timeout} = 2 * 60 * 1000;
    
    return $this;
}

#= connectionListener Methods =================================================
sub abortIncoming {
    my $this = shift;
    while (@{$this->{_incoming}}) {
        my $req = shift @{$this->{_incoming}};
        $req->emit('aborted');
        $req->emit('close');
    }
    # abort socket._httpMessage ?
}

sub serverSocketCloseListener {
    my $this = shift;
    my $server = $this->{server};
    if ($server->{parser}) {
        freeParser($server->{parser});
    }
    abortIncoming($server);
}

sub socketOnError {
    my ($this,$e) = @_;
    my $server = $this->{server};
    $server->emit('clientError', $e, $this);
}

sub socketOnData {
    my ($this,$d) = @_;
    my $socket = $this;
    assert(!$socket->{_paused});
    my $parser = $socket->{parser};
    my $self = $socket->{server};
    
    debug('SERVER socketOnData %d', $util->BufferOrStringLength($d));
    my $ret = $parser->execute($d);
    if (ref $ret eq 'Rum::Error') {
        debug('parse error');
        $socket->destroy($ret);
    } elsif ($parser->{incoming} && $parser->{incoming}->{upgrade}) {
        #Upgrade or CONNECT
        my $bytesParsed = $ret;
        my $req = $parser->{incoming};
        debug('SERVER upgrade or connect', $req->{method});
        
        $socket->removeListener('data', \&socketOnData);
        $socket->removeListener('end', \&socketOnEnd);
        $socket->removeListener('close', \&serverSocketCloseListener);
        $parser->finish();
        freeParser($parser, $req);
        
        my $eventName = $req->{method} eq 'CONNECT' ? 'connect' : 'upgrade';
        if (Rum::Events::listenerCount($self, $eventName) > 0) {
            debug('SERVER have listener for %s', $eventName);
            my $bodyHead = $d->slice($bytesParsed, $d->length);
            #TODO(isaacs): Need a way to reset a stream to fresh state
            #IE, not flowing, and not explicitly paused.
            $socket->{_readableState}->{flowing} = undef;
            $self->emit($eventName, $req, $socket, $bodyHead);
        } else {
            #Got upgrade header or CONNECT method, but have no handler.
            $socket->destroy();
        }
    }
    
    if ($socket->{_paused}) {
        #onIncoming paused the socket, we should pause the parser as well
        debug('pause parser');
        $socket->{parser}->pause();
    }
}

sub socketOnEnd {
    my $socket = shift;
    my $parser = $socket->{parser};
    my $server = $socket->{server};
    
    my $ret = $parser->finish();
    
    if (ref $ret eq 'Rum::Error') {
        debug('parse error');
        $socket->destroy($ret);
        return;
    }
    
    if (!$server->{httpAllowHalfOpen}) {
        abortIncoming($server);
        if ($socket->{writable}) { $socket->end() }
    } elsif (@{$server->{_outgoing}}) {
        $server->{_outgoing}->[@{$server->{_outgoing}} - 1]->{_last} = 1;
    } elsif ($socket->{_httpMessage}) {
        $socket->{_httpMessage}->{_last} = 1;
    } else {
        if ($socket->{writable}) { $socket->end() }
    }
}

sub socketOnDrain {
    my $socket = shift;
    # If we previously paused, then start reading again.
    if ($socket->{_paused}) {
        $socket->{_paused} = 0;
        $socket->{parser}->resume();
        $socket->resume();
    }
}

sub socketOnTimeout {
    my $socket = shift;
    my $server = $socket->{server};
    my $req = $socket->{parser} && $socket->{parser}->{incoming};
    my $reqTimeout = $req && !$req->{complete} && $req->emit('timeout', $socket);
    my $res = $socket->{_httpMessage};
    my $resTimeout = $res && $res->emit('timeout', $socket);
    my $serverTimeout = $server->emit('timeout', $socket);
    
    if (!$reqTimeout && !$resTimeout && !$serverTimeout) {
        $socket->destroy();
    }
}

sub resOnFinish {
    my $res = shift;
    my $socket = $res->{socket};
    my $server = $socket->{server};
    my $req = delete $res->{req};
    
    #Usually the first incoming element should be our request. it may
    #be that in the case abortIncoming() was called that the incoming
    #array will be empty.
    assert(@{$server->{_incoming}} == 0 || $server->{_incoming}->[0] == $req);
    
    shift @{$server->{_incoming}};
    
    #if the user never called req.read(), and didn't pipe() or
    #.resume() or .on('data'), then we call req._dump() so that the
    #bytes will be pulled off the wire.
    if (!$req->{_consuming}) {
        $req->_dump();
    }
    
    $res->detachSocket($socket);
    
    if ($res->{_last}) {
        $socket->destroySoon();
    } else {
        #start sending the next message
        my $m = shift @{$server->{_outgoing}};
        if ($m) {
            $m->assignSocket($socket);
        }
    }
}

sub parserOnIncoming {
    my ($this, $req, $shouldKeepAlive) = @_;
    my $socket = $this->{socket};
    my $server = $socket->{server};
    
    push @{$server->{_incoming}}, $req;
    
    #If the writable end isn't consuming, then stop reading
    #so that we don't become overwhelmed by a flood of
    #pipelined requests that may never be resolved.
    if (!$socket->{_paused}) {
        my $needPause = $socket->{_writableState}->{needDrain};
        if ($needPause) {
            $socket->{_paused} = 1;
            #We also need to pause the parser, but don't do that until after
            #the call to execute, because we may still be processing the last
            #chunk.
            $socket->pause();
        }
    }
    
    my $res = Rum::HTTP::Server::Response->new($req);
    
    $res->{shouldKeepAlive} = $shouldKeepAlive;
    #DTRACE_HTTP_SERVER_REQUEST(req, socket);
    #COUNTER_HTTP_SERVER_REQUEST();
    
    if ($socket->{_httpMessage}) {
        #There are already pending outgoing res, append.
        push @{$server->{_outgoing}}, $res;
    } else {
        $res->assignSocket($socket);
    }
    
    #When we're finished writing the response, check if this is the last
    #respose, if so destroy the socket.
    $res->on('prefinish', \&resOnFinish);
    
    if (!$util->isUndefined($req->{headers}->{expect}) &&
        ($req->{httpVersionMajor} == 1 && $req->{httpVersionMinor} == 1) &&
        $req->{headers}->{'expect'} =~ $continueExpression ) {
        $res->{_expect_continue} = 1;
        if (Rum::Events::listenerCount($server, 'checkContinue') > 0) {
            $server->emit('checkContinue', $req, $res);
        } else {
            $res->writeContinue();
            $server->emit('request', $req, $res);
        }
    } else {
        $server->emit('request', $req, $res);
    }
    return 0; # Not a HEAD response. (Not even a response!)
}

sub connectionListener {
    my ($this, $socket) = @_;
    my $self = $this;
    
    $this->{_incoming} = [];
    $this->{_outgoing} = [];
    
    debug('SERVER new http connection');
    
    httpSocketSetup($socket);
    
    #If the user has added a listener to the server,
    #request, or response, then it's their responsibility.
    #otherwise, destroy on timeout by default
    if ($self->{timeout}) {
        $socket->setTimeout($self->{timeout});
    }
    
    $socket->on('timeout', \&socketOnTimeout);
    
    my $parser = $parsers->alloc();
    $parser->reinitialize('REQUEST');
    weaken($parser->{socket} = $socket);
    $socket->{parser} = $parser;
    $parser->{incoming} = undef;
    
    #Propagate headers limit from server instance to parser
    if ($util->isNumber($this->{maxHeadersCount})) {
        $parser->{maxHeaderPairs} = $this->{maxHeadersCount} << 1;
    } else {
        #Set default value because parser may be reused from FreeList
        $parser->{maxHeaderPairs} = 2000;
    }
    
    $socket->addListener('close', \&serverSocketCloseListener);
    
    #TODO(isaacs): Move all these functions out of here
    
    $socket->addListener('error', \&socketOnError);
    
    $socket->on('data', \&socketOnData);
    
    $socket->on('end', \&socketOnEnd);
    #The following callback is issued after the headers have been read on a
    #new message. In this callback we setup the response object and pass it
    #to the user.
    
    $socket->{_paused} = 0;
    
    $socket->on('drain', \&socketOnDrain);
    
    $parser->{onIncoming} = \&parserOnIncoming;
    weaken $socket;
}

########################################################


package Rum::HTTP::Server::Response; {
    use strict;
    use warnings;
    use Data::Dumper;
    use Rum::Loop::Utils 'assert';
    use base 'Rum::HTTP::Outgoing';
    sub new {
        my ($class,$req) = @_;
        my $this = bless {}, $class;
        Rum::HTTP::Outgoing::new($this);
        $this->{statusCode} = 200;
        $this->{req} = $req;
        if ($req->{method} eq 'HEAD') {$this->{_hasBody} = 0}
        $this->{sendDate} = 1;
        
        if ($req->{httpVersionMajor} < 1 || $req->{httpVersionMinor} < 1) {
            $this->{useChunkedEncodingByDefault} = defined $req->{headers}->{te}
                            && $req->{headers}->{te} =~ $chunkExpression;
            $this->{shouldKeepAlive} = 0;
        }
        
        return $this;
    }
    
    sub assignSocket {
        my ($this, $socket) = @_;
        assert(!$socket->{_httpMessage});
        $socket->{_httpMessage} = $this;
        $this->{socket} = $socket;
        $this->{connection} = $socket;
        $socket->on('close', \&onServerResponseClose);
        $this->emit('socket', $socket);
        $this->_flush();
    }
    
    sub writeHead {
        my $this = shift;
        my ($statusCode) = @_;
        
        my ($headers, $headerIndex);
        
        if ($util->isString($_[1])) {
            $this->{statusMessage} = $_[1];
            $headerIndex = 2;
        } else {
            $this->{statusMessage} =
                $this->{statusMessage} || $STATUS_CODES{$statusCode} || 'unknown';
            $headerIndex = 1;
        }
        
        $this->{statusCode} = $statusCode;
        
        my $obj = $_[$headerIndex];
        
        if ($this->{_headers}) {
            #Slow-case: when progressive API and header fields are passed.
            if ($obj) {
                my @keys = keys %{$obj};
                for (my $i = 0; $i < @keys; $i++) {
                    my $k = $keys[$i];
                    if ($k) { $this->setHeader($k, $obj->[$k]) }
                }
            }
            #only progressive api is used
            $headers = $this->_renderHeaders();
        } else {
            #only writeHead() called
            $headers = $obj;
        }
        
        my $statusLine = 'HTTP/1.1 ' . $statusCode . ' ' .
                   $this->{statusMessage} . $CRLF;
        
        if ($statusCode == 204 || $statusCode == 304 ||
            (100 <= $statusCode && $statusCode <= 199)) {
            #RFC 2616, 10.2.5:
            #The 204 response MUST NOT include a message-body, and thus is always
            #terminated by the first empty line after the header fields.
            #RFC 2616, 10.3.5:
            #The 304 response MUST NOT contain a message-body, and thus is always
            #terminated by the first empty line after the header fields.
            #RFC 2616, 10.1 Informational 1xx:
            #This class of status code indicates a provisional response,
            #consisting only of the Status-Line and optional headers, and is
            #terminated by an empty line.
            $this->{_hasBody} = 0;
        }
        
        #don't keep alive connections where the client expects 100 Continue
        #but we sent a final status; they may put extra bytes on the wire.
        if ($this->{_expect_continue} && !$this->{_sent100}) {
            $this->{shouldKeepAlive} = 0;
        }
        
        $this->_storeHeader($statusLine, $headers);
    }
    
    sub onServerResponseClose {
        my $this = shift;
        # EventEmitter.emit makes a copy of the 'close' listeners array before
        # calling the listeners. detachSocket() unregisters onServerResponseClose
        # but if detachSocket() is called, directly or indirectly, by a 'close'
        # listener, onServerResponseClose is still in that copy of the listeners
        # array. That is, in the example below, b still gets called even though
        # it's been removed by a:
        #
        # var obj = new events.EventEmitter;
        # obj.on('event', a);
        # obj.on('event', b);
        # function a() { obj.removeListener('event', b) }
        # function b() { throw "BAM!" }
        # obj.emit('event'); // throws
        #
        # Ergo, we need to deal with stale 'close' events and handle the case
        # where the ServerResponse object has already been deconstructed.
        # Fortunately, that requires only a single if check. :-)
        if ($this->{_httpMessage}){ $this->{_httpMessage}->emit('close') }
    }
    
    sub detachSocket {
        my $this = shift;
        my $socket = shift;
        assert($socket->{_httpMessage} == $this);
        $socket->removeListener('close', \&onServerResponseClose);
        $socket->{_httpMessage} = undef;
        $this->{socket} = $this->{connection} = undef;
    }
    
    sub _implicitHeader {
        my $this = shift;
        $this->writeHead($this->{statusCode});
    }
    
}


1;

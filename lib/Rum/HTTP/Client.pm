package Rum::HTTP::Client;
use strict;
use warnings;
use Rum qw[Require process];
use Rum::HTTP::Agent;
use Rum::HTTP::Common;
use Rum::Loop::Utils 'assert';
use base qw[Rum::HTTP::Outgoing];
my $url;
my $util = 'Rum::Utils';

my $net;
my $Agent = Require('_http_agent');
use Data::Dumper;

my $parsers = $Rum::HTTP::Common::parsers;
*httpSocketSetup = \&Rum::HTTP::Common::httpSocketSetup;
*debug = \&Rum::HTTP::Common::debug;
*freeParser = \&Rum::HTTP::Common::freeParser;

sub new {
    my ($this, $options, $cb) = @_;
    $this = ref $this ? $this : bless({}, __PACKAGE__);
    
    my $self = $this;
    Rum::HTTP::Outgoing::new($self);
    
    if ($util->isString($options)) {
        $options = $url->parse($options);
    } else {
        $options = $util->_extend({}, $options);
    }
    
    my $agent = $options->{agent};
    my $defaultAgent = $options->{_defaultAgent} || $Rum::HTTP::Agent::globalAgent;
    
    if (defined $agent && $agent == 0) { #false
        my $package = ref $defaultAgent;
        $agent = $package->new();
    } elsif (!$agent && !$options->{createConnection}) {
        $agent = $defaultAgent;
    }
    
    $self->{agent} = $agent;
    
    my $protocol = $options->{protocol} || $defaultAgent->{protocol};
    my $expectedProtocol = $defaultAgent->{protocol};
    if ($self->{agent} && $self->{agent}->{protocol}) {
        $expectedProtocol = $self->{agent}->{protocol};
    }

    if ($options->{path} && $options->{path} =~ / /) {
        # The actual regex is more like /[^A-Za-z0-9\-._~!$&'()*+,;=/:@]/
        # with an additional rule for ignoring percentage-escaped characters
        # but that's a) hard to capture in a regular expression that performs
        # well, and b) possibly too restrictive for real-world usage. That's
        # why it only scans for spaces because those are guaranteed to create
        # an invalid request.
        Rum::Error->new('Request path contains unescaped characters.')->throw;
    } elsif ($protocol ne $expectedProtocol) {
        Rum::Error->new('Protocol "' . $protocol . '" not supported. ' .
                    'Expected "' . $expectedProtocol . '".')->throw;
    }
    
    my $defaultPort = $options->{defaultPort} || $self->{agent} &&
                        $self->{agent}->{defaultPort};
    
    my $port = $options->{port} = $options->{port} || $defaultPort || 80;
    my $host = $options->{host} = $options->{hostname} ||
                $options->{host} || 'localhost';
    
    my $setHost;
    if (!defined $options->{setHost}) {
        $setHost = 1;
    }
    
    $self->{socketPath} = $options->{socketPath};
    
    my $method = $self->{method} = uc($options->{method} || 'GET');
    $self->{path} = $options->{path} || '/';
    if ($cb) {
        $self->once('response', $cb);
    }
    
    if (ref $options->{headers} ne 'ARRAY') {
        if ($options->{headers}) {
            my @keys = keys %{$options->{headers}};
            my $l;
            ##FIXME : use perl loop
            for (my $i = 0, $l = scalar @keys; $i < $l; $i++) {
                my $key = $keys[$i];
                $self->setHeader($key, $options->{headers}->{$key});
            }
        }
        if ($host && !$this->getHeader('host') && $setHost) {
            my $hostHeader = $host;
            if ($port && +$port != $defaultPort) {
                $hostHeader .= ':' . $port;
            }
            $this->setHeader('Host', $hostHeader);
        }
    }
    
    if ($options->{auth} && !$this->getHeader('Authorization')) {
        #basic auth
        $this->setHeader('Authorization', 'Basic ' .
                   Rum::Buffer->new($options->{auth})->toString('base64'));
    }
    
    if ($method eq 'GET' ||
        $method eq 'HEAD' ||
        $method eq 'DELETE' ||
        $method eq 'OPTIONS' ||
        $method eq 'CONNECT') {
        $self->{useChunkedEncodingByDefault} = 0;
    } else {
        $self->{useChunkedEncodingByDefault} = 1;
    }
    
    if (ref $options->{headers} eq 'ARRAY') {
        $self->_storeHeader($self->{method} . ' ' . $self->{path} . " HTTP/1.1\r\n",
                      $options->{headers});
    } elsif ($self->getHeader('expect')) {
        $self->_storeHeader($self->{method} . ' ' . $self->{path} + " HTTP/1.1\r\n",
                      $self->_renderHeaders());
    }
    
    my $conn;
    if ($self->{socketPath}) {
        $self->{_last} = 1;
        $self->{shouldKeepAlive} = 0;
        $conn = $self->{agent}->createConnection({ path => $self->{socketPath} });
        $self->onSocket($conn);
    } elsif ($self->{agent}) {
        # If there is an agent we should default to Connection:keep-alive,
        # but only if the Agent will actually reuse the connection!
        # If it's not a keepAlive agent, and the maxSockets==Infinity, then
        # there's never a case where this socket will actually be reused
        if (!$self->{agent}->{keepAlive} &&
             !$util->isFinite($self->{agent}->{maxSockets})) {
            
            $self->{_last} = 1;
            $self->{shouldKeepAlive} = 0;
        } else {
            $self->{_last} = 0;
            $self->{shouldKeepAlive} = 1;
        }
        $self->{agent}->addRequest($self, $options);
    } else {
        #No agent, default to Connection:close.
        $self->{_last} = 1;
        $self->{shouldKeepAlive} = 0;
        if ($options->{createConnection}) {
            $conn = $options->{createConnection}->($options);
        } else {
            debug('CLIENT use net.createConnection', $options);
            $conn = $net->createConnection($options);
        }
        $self->onSocket($conn);
    }
    
    $self->_deferToConnect(undef, undef, sub {
        $self->_flush();
        #$self = undef; #FIXME : this is being called beofre too soon
    });
    
    return $self;
}

sub createHangUpError {
  my $error = Rum::Error->new('socket hang up');
  $error->{code} = 'ECONNRESET';
  return $error;
}

sub _implicitHeader {
    my $this = shift;
    $this->_storeHeader($this->{method} . ' ' . $this->{path} . " HTTP/1.1\r\n",
                    $this->_renderHeaders());
}

sub onSocket {
    my ($this, $socket) = @_;
    my $req = $this;
    process->nextTick( sub {
        if ($req->{aborted}) {
            # If we were aborted while waiting for a socket, skip the whole thing.
            $socket->emit('free');
        } else {
            tickOnSocket($req, $socket);
        }
    });
}

sub _deferToConnect {
    my ($this, $method, $arguments_, $cb) = @_;
    #This function is for calls that need to happen once the socket is
    #connected and writable. It's an important promisy thing for all the socket
    #calls that happen either now (when a socket is assigned) or
    #in the future (when a socket gets assigned out of the pool and is
    #eventually writable).
    my $self = $this;
    my $onSocket = sub {
        if ($self->{socket}->{writable}) {
            if ($method) {
                $self->{socket}->{$method}->($self->{socket}, @{$arguments_});
            }
            if ($cb) { $cb->(); }
        } else {
            $self->{socket}->once('connect', sub {
                if ($method) {
                    $self->{socket}->{$method}->($self->{socket}, @{$arguments_});
                }
                if ($cb) { $cb->(); }
            });
        }
    };
    
    if (!$self->{socket}) {
        $self->once('socket', $onSocket);
    } else {
        $onSocket->();
    }
}

sub socketOnData {
    my $this = shift;
    my $d = shift;
    my $socket = $this;
    my $req = $this->{_httpMessage};
    my $parser = $this->{parser};
    
    assert($parser && $parser->{socket} == $socket);
    
    my $ret = $parser->execute($d);
    if (ref $ret eq 'Rum::Error') {
        debug('parse error');
        freeParser($parser, $req);
        $socket->destroy();
        $req->emit('error', $ret);
        $req->{socket}->{_hadError} = 1;
    } elsif ($parser->{incoming} && $parser->{incoming}->{upgrade}) {
        #Upgrade or CONNECT
        my $bytesParsed = $ret;
        my $res = $parser->{incoming};
        $req->{res} = $res;
        
        $socket->removeListener('data', \&socketOnData);
        $socket->removeListener('end', \&socketOnEnd);
        $parser->finish();
        
        my $bodyHead = $d->slice($bytesParsed, $d->length);
        
        my $eventName = $req->{method} eq 'CONNECT' ? 'connect' : 'upgrade';
        if (Rum::Events::listenerCount($req, $eventName) > 0) {
            $req->{upgradeOrConnect} = 1;
            
            #detach the socket
            $socket->emit('agentRemove');
            $socket->removeListener('close', \&socketCloseListener);
            $socket->removeListener('error', \&socketErrorListener);
            
            #TODO(isaacs): Need a way to reset a stream to fresh state
            #IE, not flowing, and not explicitly paused.
            $socket->{_readableState}->{flowing} = undef;
            
            $req->emit($eventName, $res, $socket, $bodyHead);
            $req->emit('close');
        } else {
            #Got Upgrade header or CONNECT method, but have no handler.
            $socket->destroy();
        }
        freeParser($parser, $req);
    } elsif ($parser->{incoming} && $parser->{incoming}->{complete} &&
             #When the status code is 100 (Continue), the server will
             #send a final response after this client sends a request
             #body. So, we must not free the parser.
             $parser->{incoming}->{statusCode} != 100) {
        
        $socket->removeListener('data', \&socketOnData);
        $socket->removeListener('end', \&socketOnEnd);
        freeParser($parser, $req);
    }
}

sub tickOnSocket {
    my ($req, $socket) = @_;
    
    my $parser = $parsers->alloc();
    $req->{socket} = $socket;
    $req->{connection} = $socket;
    $parser->reinitialize('RESPONSE');
    $parser->{socket} = $socket;
    $parser->{incoming} = undef;
    $req->{parser} = $parser;
    
    $socket->{parser} = $parser;
    $socket->{_httpMessage} = $req;
    
    # Setup "drain" propogation.
    httpSocketSetup($socket);
    
    #Propagate headers limit from request object to parser
    if ($util->isNumber($req->{maxHeadersCount})) {
        $parser->{maxHeaderPairs} = $req->{maxHeadersCount} << 1;
    } else {
        # Set default value because parser may be reused from FreeList
        $parser->{maxHeaderPairs} = 2000;
    }
    
    $parser->{onIncoming} = \&parserOnIncomingClient;
    $socket->on('error', \&socketErrorListener);
    $socket->on('data', \&socketOnData);
    $socket->on('end', \&socketOnEnd);
    $socket->on('close', \&socketCloseListener);
    $req->emit('socket', $socket);
}

sub socketErrorListener {
    my ($this, $err) = @_;
    my $socket = $this;
    my $parser = $socket->{parser};
    my $req = $socket->{_httpMessage};
    debug('SOCKET ERROR:', $err->{message}, $err);

    if ($req) {
        $req->emit('error', $err);
        #For Safety. Some additional errors might fire later on
        #and we need to make sure we don't double-fire the error event.
        $req->{socket}->{_hadError} = 1;
    }
    
    if ($parser) {
        $parser->finish();
        freeParser($parser, $req);
    }
    $socket->destroy();
}


#client
sub parserOnIncomingClient {
    my ($this, $res, $shouldKeepAlive) = @_;
    my $socket = $this->{socket};
    my $req = $socket->{_httpMessage};
    
    #propogate "domain" setting...
    if ($req->{domain} && !$res->{domain}) {
        debug('setting "res.domain"');
        $res->{domain} = $req->{domain};
    }
    
    debug('AGENT incoming response!');
    
    if ($req->{res}) {
        #We already have a response object, this means the server
        #sent a double response.
        $socket->destroy();
        return;
    }
    
    $req->{res} = $res;
    
    #Responses to CONNECT request is handled as Upgrade.
    if ($req->{method} eq 'CONNECT') {
        $res->{upgrade} = 1;
        return 1; # skip body
    }
    
    #Responses to HEAD requests are crazy.
    #HEAD responses aren't allowed to have an entity-body
    #but *can* have a content-length which actually corresponds
    #to the content-length of the entity-body had the request
    #been a GET.
    my $isHeadResponse = $req->{method} eq 'HEAD';
    debug('AGENT isHeadResponse', $isHeadResponse);
    
    if ($res->{statusCode} == 100) {
        #restart the parser, as this is a continue message.
        delete $req->{res}; # Clear res so that we don't hit double-responses.
        $req->emit('continue');
        return 1;
    }
    
    if ($req->{shouldKeepAlive} && !$shouldKeepAlive && !$req->{upgradeOrConnect}) {
        #Server MUST respond with Connection:keep-alive for us to enable it.
        #If we've been upgraded (via WebSockets) we also shouldn't try to
        #keep the connection open.
        $req->{shouldKeepAlive} = 0;
    }
    
    
    #DTRACE_HTTP_CLIENT_RESPONSE(socket, req);
    #COUNTER_HTTP_CLIENT_RESPONSE();
    $req->{res} = $res;
    $res->{req} = $req;
    
    #add our listener first, so that we guarantee socket cleanup
    $res->on('end', \&responseOnEnd);
    my $handled = $req->emit('response', $res);
    
    #If the user did not listen for the 'response' event, then they
    #can't possibly read the data, so we ._dump() it into the void
    #so that the socket doesn't hang there in a paused state.
    if (!$handled) {
        $res->_dump();
    }
    
    return $isHeadResponse;
}

sub socketOnEnd {
    my $this = shift;
    my $socket = $this;
    my $req = $this->{_httpMessage};
    my $parser = $this->{parser};
    
    if (!$req->{res} && !$req->{socket}->{_hadError}) {
        #If we don't have a response then we know that the socket
        #ended prematurely and we need to emit an error on the request.
        $req->emit('error', createHangUpError());
        $req->{socket}->{_hadError} = 1;
    }
  
    if ($parser) {
        $parser->finish();
        freeParser($parser, $req);
    }
    
    $socket->destroy();
}

sub socketCloseListener {
    my $this = shift;
    my $socket = $this;
    my $req = $socket->{_httpMessage};
    debug('HTTP socket close');
    
    #Pull through final chunk, if anything is buffered.
    #the ondata function will handle it properly, and this
    #is a no-op if no final chunk remains.
    $socket->read();
    
    #NOTE: Its important to get parser here, because it could be freed by
    #the `socketOnData`.
    my $parser = $socket->{parser};
    $req->emit('close');
    if ($req->{res} && $req->{res}->{readable}) {
        #Socket closed before we emitted 'end' below.
        $req->{res}->emit('aborted');
        my $res = $req->{res};
        $res->on('end', sub {
            $res->emit('close');
        });
        $res->push(undef);
    } elsif (!$req->{res} && !$req->{socket}->{_hadError}) {
        #This socket error fired before we started to
        #receive a response. The error needs to
        #fire on the request.
        $req->emit('error', createHangUpError());
        $req->{socket}->{_hadError} = 1;
    }
    
    #Too bad. That output wasn't getting written.
    #This is pretty terrible that it doesn't raise an error.
    #Fixed better in v0.10
    if (@{$req->{output}}) {
        $req->{output} = [];
    }
    
    if (@{$req->{outputEncodings}}){
        $req->{outputEncodings} = [];
    }
    
    if ($parser) {
        $parser->finish();
        freeParser($parser, $req);
    }
}

sub responseOnEnd {
    my $this = shift;
    my $res = $this;
    my $req = $res->{req};
    my $socket = $req->{socket} || $res->{socket};
    
    if (!$req->{shouldKeepAlive}) {
        if ($socket->{writable}) {
            debug('AGENT socket.destroySoon()');
            $socket->destroySoon();
        }
        assert(!$socket->{writable});
    } else {
        debug('AGENT socket keep-alive');
        if ($req->{timeoutCb}) {
            $socket->setTimeout(0, $req->{timeoutCb});
            undef $req->{timeoutCb};
        }
        $socket->removeListener('close', \&socketCloseListener);
        $socket->removeListener('error', \&socketErrorListener);
        #Mark this socket as available, AFTER user-added end
        #handlers have a chance to run.
        process->nextTick(sub {
            $socket->emit('free');
        });
    }
}

sub abort {
    my $this = shift;
    # Mark as aborting so we can avoid sending queued request data
    # This is used as a truthy flag elsewhere. The use of Date.now is for
    # debugging purposes only.
    $this->{aborted} = time;
    
    #If we're aborting, we don't care about any more response data.
    if ($this->{res}) {
        $this->{res}->_dump();
    } else {
        $this->once('response', sub {
            my ($this, $res) = @_;
            $res->_dump();
        });
    }
    
    # In the event that we don't have a socket, we will pop out of
    # the request queue through handling in onSocket.
    if ($this->{socket}) {
        # in-progress
        $this->{socket}->destroy();
    }
}

1;

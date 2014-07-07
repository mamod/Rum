package Rum::Net::Socket;
use strict;
use warnings;
use lib '../../';
use Rum::Utils;
use base qw/Rum::Stream::Duplex Rum::Stream::Writable/;
use Rum::Loop::Utils 'assert';
use Rum::Wrap::TTY;
use Rum::Net::Server;
use Carp;
use Data::Dumper;

sub errnoException { &Rum::Utils::_errnoException }

my $util = 'Rum::Utils';
my $EOF = -4095;

sub debug {
    return;
    print "NET $$: ";
    for (@_){
        if (CORE::ref $_){
            print STDERR Dumper $_;
        } elsif (defined $_) {
            print STDERR $_ . " ";
        } else {
            print STDERR "undefined ";
        }
    }
    print STDERR "\n";
}

sub new {
    my $class = shift;
    my $options = shift;
    
    my $this = CORE::ref $class ? $class : bless {}, $class;

    $this->{_connecting} = 0;
    $this->{_hadError} = 0;
    $this->{_handle} = undef;
    $this->{_host} = undef;
    
    if ($util->isNumber($options)) {
        open(my $fh, "+<&=", $options) or die $! . " $options";
        $options = {
            fd => $options,
            fh => $fh
        };
    } elsif (CORE::ref $options ne 'HASH' &&
                    Rum::Wrap::TTY::guessHandleType($options) ne 'UNKNOWN') {
        $options = {
            fh => $options,
            fd => fileno $options
        };
    } elsif ($util->isUndefined($options)) {
        $options = {};
    }
    
    if ($options->{fd} && !$options->{fh}) {
        open(my $fh, ">&=", $options->{fd}) or die $!;
        $options->{fh} = $fh;
    } elsif ($options->{fh} && !$options->{fd}){
        $options->{fd} = fileno $options->{fh};
    }
    
    Rum::Stream::Duplex::new($this, $options);
    #stream.Duplex.call(this, options);

    if ($options->{handle}) {
        $this->{_handle} = $options->{handle};
    } elsif (!$util->isUndefined($options->{fd}) ) {
        $this->{_handle} = createHandle($options->{fh});
        $this->{_handle}->open2($options->{fh});
        $this->{readable} = $options->{readable} != 0;
        $this->{writable} = $options->{writable} != 0;
    } else {
        #these will be set once there is a connection
        $this->{readable} = $this->{writable} = 0;
    }

    #shut down the socket when we're finished with it.
    $this->on('finish', \&onSocketFinish);
    $this->on('_socketEnd', \&onSocketEnd);
    
    initSocketHandle($this);
    
    $this->{_pendingData} = undef;
    $this->{_pendingEncoding} = '';
    
    #handle strings directly
    $this->{_writableState}->{decodeStrings} = 0;
    
    #default to *not* allowing half open sockets
    $this->{allowHalfOpen} = $options && $options->{allowHalfOpen} || 0;

    #if we have a handle, then start the flow of data into the
    #buffer. if not, then this will happen when we connect
    if ($this->{_handle} && (!defined $options->{readable} || $options->{readable})) {
        $this->read(0);
    }
    
    return $this;
}

sub createHandle {
    my $fd = shift;
    my $type = Rum::Wrap::TTY::guessHandleType($fd);
    if ($type eq 'PIPE') { return Rum::Net::Server::createPipe() };
    if ($type eq 'TCP')  {  return Rum::Net::Server::createTCP() };
    
    die "unsupported fd type " . $type;
    #throw new TypeError('Unsupported fd type: ' + type);
}

sub setTimeout {
    my ($this, $msecs, $callback) = @_;
    $this->{_onTimeout} = 1;
    if ($util->isNumber($msecs) && $msecs > 0) {
        Rum::Timers::enroll($this, $msecs);
        Rum::Timers::_unrefActive($this);
        if ($callback) {
            $this->once('timeout', $callback);
        }
    } elsif ($msecs == 0) {
        Rum::Timers::unenroll($this);
        if ($callback) {
            $this->removeListener('timeout', $callback);
        }
    }
}

sub _onTimeout {
    debug('_onTimeout');
    shift->emit('timeout');
}

sub bufferSize {
    my $this = shift;
    if ( $this->{_handle} ) {
        return $this->{_handle}->{writeQueueSize} + $this->{_writableState}->{length};
    }
}

#the user has called .end(), and all the bytes have been
#sent out to the other side.
#If allowHalfOpen is false, or if the readable side has
#ended already, then destroy.
#If allowHalfOpen is true, then we need to do a shutdown,
#so that only the writable side will be cleaned up.
sub onSocketFinish {
    
    my $this = shift;
    
    #If still connecting - defer handling 'finish' until 'connect' will happen
    if ($this->{_connecting}) {
        debug('osF: not yet connected');
        return $this->once('connect', \&onSocketFinish);
    }
  
    debug('onSocketFinish');
    if (!$this->{readable} || $this->{_readableState}->{ended}) {
        debug('oSF: ended, destroy', $this->{_readableState});
        return $this->destroy();
    }
  
    debug('oSF: not ended, call shutdown()');
  
    #otherwise, just shutdown, or destroy() if not possible
    if (!$this->{_handle} ){
        return $this->destroy();
    }
  
    my $req = { oncomplete => \&afterShutdown };
    my $err = $this->{_handle}->shutdown($req);
  
    if ($err){
        return $this->_destroy(errnoException($err, 'shutdown'));
    }
}

sub afterShutdown {
    my ($status, $handle, $req) = @_;
    my $self = $handle->{owner};
    
    debug('afterShutdown destroyed=%j', $self->{destroyed},
        $self->{_readableState});

    #callback may come after call to destroy.
    if ($self->{destroyed}) {
        return;
    }
    
    if ($self->{_readableState}->{ended}) {
        debug('readableState ended, destroying');
        $self->destroy();
    } else {
        $self->once('_socketEnd', \&destroy);
    }
}

sub initSocketHandle {
    my $self = shift;
    $self->{destroyed} = 0;
    $self->{bytesRead} = 0;
    $self->{_bytesDispatched} = 0;

    #Handle creation may be deferred to bind() or connect() time.
    if ($self->{_handle}) {
        $self->{_handle}->{owner} = $self;
        $self->{_handle}->{onread} = \&onread;
        
        #If handle doesn't support writev - neither do we
        if (!$self->{_handle}->{writev}){
            $self->{_writev} = 0;
        }
    }
}


#This function is called whenever the handle gets a
#buffer, or when there's an error reading.
sub onread {
    my ($this, $nread, $buffer) = @_;
    my $handle = $this;
    my $self = $handle->{owner};
    assert($handle == $self->{_handle}, 'handle != self._handle');
    
    Rum::Timers::_unrefActive($self);
    
    debug('onread', $nread);
    
    if ($nread > 0) {
        debug('got data');
        
        #read success.
        #In theory (and in practice) calling readStop right now
        #will prevent this from being called again until _read() gets
        #called again.
        
        #if it's not enough data, we'll just call handle.readStart()
        #again right away.
        $self->{bytesRead} += $nread;
        
        #Optimization: emit the original buffer with end points
        my $ret = $self->push($buffer->{base});
        
        if ($handle->{reading} && !$ret) {
            $handle->{reading} = 0;
            debug('readStop');
            my $err = $handle->readStop();
            if ($err){
                $self->_destroy(errnoException($err, 'read'));
            }
        }
        return;
    }
    
    #if we didn't get any bytes, that doesn't necessarily mean EOF.
    #wait for the next one.
    if ($nread == 0) {
        debug('not any data, keep waiting');
        return;
    }
    
    #Error, possibly EOF.
    if ($nread != $EOF) {
        return $self->_destroy($!);
    }
    
    debug('EOF');
    
    if (!$self->{_readableState}->{length}) {
        $self->{readable} = 0;
        maybeDestroy($self);
    }
    
    #push a null to signal the end of data.
    $self->push(undef);
    
    #internal end event so that we know that the actual socket
    #is no longer readable, and we can start the shutdown
    #procedure. No need to wait for all the data to be consumed.
    $self->emit('_socketEnd');
}

sub maybeDestroy {
    my $socket = shift;
    if (!$socket->{readable} &&
        !$socket->{writable} &&
        !$socket->{destroyed} &&
        !$socket->{_connecting} &&
        !$socket->{_writableState}->{length}) {
        $socket->destroy();
    }
}

sub destroySoon {
    my $this = shift;
    if ($this->{writable}){
        $this->end();
    }

    if ($this->{_writableState}->{finished}){
        $this->destroy();
    } else {
        $this->once('finish', \&destroy);
    }
}

sub onSocketEnd {
    my $this = shift;
    #XXX Should not have to do as much crap in this function.
    #ended should already be true, since this is called *after*
    #the EOF errno and onread has eof'ed
    debug('onSocketEnd', $this->{_readableState});
    $this->{_readableState}->{ended} = 1;
    if ($this->{_readableState}->{endEmitted}) {
        $this->{readable} = 0;
        maybeDestroy($this);
    } else {
        $this->once('end', sub {
            $this->{readable} = 0;
            maybeDestroy($this);
        });
        $this->read(0);
    }
  
    if (!$this->{allowHalfOpen}) {
        $this->{_write} = \&writeAfterFIN;
        $this->destroySoon();
    }
}

sub writeAfterFIN {
    die "writeAfterFIN";
}

sub _doRead {
    my $this = shift;
    my $n = shift;
    #assert(defined $n);
    if (!$n || $n == 0){
        return Rum::Stream::Readable::read($this, $n);
    }
    
    $this->{_doRead} = \&Rum::Stream::Readable::read;
    $this->{_consuming} = 1;
    return $this->read(0);
}

sub read {
    my $this = shift;
    my $n = shift;
    if (my $sub = $this->{_doRead}){
        $sub->($this,$n);
    } else {
        $this->_doRead($n);
    }
}

sub _read {
    my $this = shift;
    my $n = shift;
    
    debug('_read ');
    
    if ( $this->{_connecting} || !$this->{_handle} ) {
        debug('_read wait for connection');
        $this->once('connect', sub {
            $this->_read($n);
        });
    } elsif ( !$this->{_handle}->{reading} ) {
        #not already reading, start the flow
        debug('Socket._read readStart');
        $this->{_handle}->{reading} = 1;
        my $err = $this->{_handle}->readStart();
        
        if ($err){
            #die $!;
            $this->_destroy(errnoException($err, 'read'));
        }
    }
}

sub write {
    my ($self, $chunk, $encoding, $cb) = @_;
    if ($self->{_write}){
        return $self->{_write}->(@_);
    }
    return __write(@_);
}

sub _write {
    my ($this, $data, $encoding, $cb) = @_;
    $this->_writeGeneric(0, $data, $encoding, $cb);
}

sub __write {
    my ($self, $chunk, $encoding, $cb) = @_;
    if (!$util->isString($chunk) && !$util->isBuffer($chunk)) {
        croak('invalid data');
    }
    return Rum::Stream::Duplex::write(@_);
}

sub _writeGeneric {
    my ($this, $writev, $data, $encoding, $cb) = @_;
    #If we are still connecting, then buffer this for later.
    #The Writable logic will buffer up any more writes while
    #waiting for this one to be done.
    if ( $this->{_connecting} ) {
        $this->{_pendingData} = $data;
        $this->{_pendingEncoding} = $encoding;
        $this->once('connect', sub {
            $this->_writeGeneric($writev, $data, $encoding, $cb);
        });
        return;
    }
    
    $this->{_pendingData} = undef;
    $this->{_pendingEncoding} = '';
    
    Rum::Timers::_unrefActive($this);
    
    if (!$this->{_handle}) {
        $this->_destroy(Rum::Error->new('This socket is closed.'), $cb);
        return 0;
    }
    
    my $req = { oncomplete => \&__afterWrite, async => 0 };
    my $err;

    if ($writev) {
        die "not implemented";
        #chunks = new Array(data.length << 1);
        #for (var i = 0; i < data.length; i++) {
        #    var entry = data[i];
        #    var chunk = entry.chunk;
        #    var enc = entry.encoding;
        #    chunks[i * 2] = chunk;
        #    chunks[i * 2 + 1] = enc;
        #}
        #err = this._handle.writev(req, chunks);
        #
        ##Retain chunks
        #if (err === 0) req._chunks = chunks;
    } else {
        my $enc;
        if ($util->isBuffer($data)) {
            $req->{buffer} = $data; #Keep reference alive.
            $enc = 'buffer';
        } else {
            $enc = $encoding;
        }
        $err = createWriteReq($req, $this->{_handle}, $data, $enc);
    }
    
    if ($err){
        return $this->_destroy( errnoException($err, 'write', $req->{error}), $cb);
    }
    
    $this->{_bytesDispatched} += $req->{bytes} || 0;
    
    #If it was entirely flushed, we can write some more right now.
    #However, if more is left in the queue, then wait until that clears.
    if ($req->{async} && $this->{_handle}->{writeQueueSize} != 0){
        $req->{cb} = $cb;
    } else {
        $cb->();
    }
}

sub __afterWrite {
    
    my ($status, $handle, $req, $err) = @_;
    my $self = $handle->{owner};
    #if (self != process.stderr && self != process.stdout){
        debug('afterWrite', $status);
    #}
    
    #callback may come after call to destroy.
    if ($self->{destroyed}) {
        debug('afterWrite destroyed');
        return;
    }
    
    if ($status) {
        die "ss" . $status;
        my $ex = errnoException($status, 'write', $err);
        debug('write failure', $ex);
        $self->_destroy($ex, $req->{cb});
        return;
    }
    
    Rum::Timers::_unrefActive($self);
    
    #if (self != process.stderr && self != process.stdout) {
        debug('afterWrite call cb');
    #}

    if ($req->{cb}) {
        $req->{cb}->($self);
    }
}


sub createWriteReq {
    my ($req, $handle, $data, $encoding) = @_;
    if ($encoding eq 'buffer') {
        return $handle->writeBuffer($req, $data);
    } elsif ($encoding eq 'utf8' || $encoding eq 'utf-8'){
        return $handle->writeUtf8String($req, $data);
    } elsif ($encoding eq 'ascii'){
        return $handle->writeAsciiString($req, $data);
    } else {
        die $encoding;
    }
}

sub readyState {
    my $this = shift;
    
    if ($this->{_connecting}) {
        return 'opening';
    } elsif ($this->{readable} && $this->{writable}) {
        return 'open';
    } elsif ($this->{readable} && !$this->{writable}) {
        return 'readOnly';
    } elsif (!$this->{readable} && $this->{writable}) {
        return 'writeOnly';
    } else {
        return 'closed';
    }
}

sub destroy {
    my $this = shift;
    my $exception = shift;
    debug('destroy', $exception);
    $this->_destroy($exception);
}

#Returns an array [options] or [options, cb]
#It is the same as the argument of Socket.prototype.connect().
sub normalizeConnectArgs {
    if (CORE::ref $_[0] && CORE::ref $_[0] ne 'HASH'){
        shift;
    }
    
    my $options = {};
    
    if ($util->isObject($_[0])) {
        #connect(options, [cb])
        $options = $_[0];
    } elsif (isPipeName($_[0])) {
        #connect(path, [cb]);
        $options->{path} = $_[0];
    } else {
        #connect(port, [host], [cb])
        $options->{port} = $_[0];
        if ($util->isString($_[1])) {
            $options->{host} = $_[1];
        }
    }
    my $cb = $_[-1];
    return $util->isFunction($cb) ? ($options, $cb) : ($options);
}


sub _connect {
    my ($self, $address, $port, $addressType, $localAddress, $localPort) = @_;
    #TODO return promise from Socket.prototype.connect which
    #wraps _connectReq.
    
    assert($self->{_connecting} == 1);
    
    my $err;
    
    if ($localAddress || $localPort) {
        die "not implemented";
        
        if ($localAddress && !isIP($localAddress)) {
            $err = Rum::Error->new(
                'localAddress should be a valid IP: ' . $localAddress);
        }
        
        if ($localPort && !$util->isNumber($localPort)){
            $err = Rum::Error->new('localPort should be a number: ' . $localPort);
        }
        
        my $bind;
        
        if ($addressType == 4){
            if (!$localAddress){
                $localAddress = '0.0.0.0';
            }
            
            $bind = $self->{_handle}->{bind};
            
        } elsif ($addressType == 6){
            die "Not implemented";
        } else {
            $err = Rum::Error->new('Invalid addressType: ' . $addressType);
        }
        
        if ($err) {
            $self->_destroy($err);
            return;
        }
        
        
        debug('binding to localAddress: %s and localPort: %d',
              $localAddress,
              $localPort);
        
        #bind = bind.bind(self._handle);
        #err = bind(localAddress, localPort);
        #
        #if (err) {
        #  self._destroy(errnoException(err, 'bind'));
        #  return;
        #}
    }

    my $req = { oncomplete => \&afterConnect };
    
    if ($addressType == 6 || $addressType == 4) {
        $port = $port | 0;
        if ($port <= 0 || $port > 65535){
            die('Port should be > 0 and < 65536');
        }
        
        if ($addressType == 6) {
            $err = $self->{_handle}->connect6($req, $address, $port);
        } elsif ($addressType == 4) {
            $err = $self->{_handle}->connect($req, $address, $port);
        }
    } else {
        $err = $self->{_handle}->connect($req, $address, \&afterConnect);
    }
    
    if ($err) {
        $self->_destroy(errnoException($err, 'connect'));
    }
}


sub connect {
    my ($this, $options, $cb) = @_;
    
    if (!$this->{_write} || $this->{_write} ne \&__write) {
        $this->{_write} = \&__write;
    }
    
    if (!$util->isObject($options)) {
        #Old API:
        #connect(port, [host], [cb])
        #connect(path, [cb]);
        my @args = normalizeConnectArgs(@_);
        return $this->connect(@args);
    }
    
    if ($this->{destroyed}) {
        $this->{_readableState}->{reading} = 0;
        $this->{_readableState}->{ended} = 0;
        $this->{_readableState}->{endEmitted} = 0;
        $this->{_writableState}->{ended} = 0;
        $this->{_writableState}->{ending} = 0;
        $this->{_writableState}->{finished} = 0;
        $this->{destroyed} = 0;
        undef $this->{_handle};
    }
    
    my $self = $this;
    my $pipe = !!$options->{path};
    debug('pipe', $pipe, $options->{path});
    
    if (!$this->{_handle}) {
        $this->{_handle} = $pipe ? Rum::Net::Server::createPipe() : Rum::Net::Server::createTCP();
        initSocketHandle($this);
    }

    if ($util->isFunction($cb)) {
        $self->once('connect', $cb);
    }

    Rum::Timers::_unrefActive($this);
    
    $self->{_connecting} = 1;
    $self->{writable} = 1;
    
    if ($pipe) {
        _connect($self, $options->{path});
    } elsif (!$options->{host}) {
        debug('connect: missing host');
        $self->{_host} = '127.0.0.1';
        _connect($self, $self->{_host}, $options->{port}, 4);
    } else {
        my $host = $options->{host};
        my $family = $options->{family} || 4;
        debug('connect: find host ' . $host);
        $self->{_host} = $host;
        Require('dns')->lookup($host, $family, sub {
            my ($err, $ip, $addressType) = @_;
            $self->emit('lookup', $err, $ip, $addressType);
            
            #It's possible we were destroyed while looking this up.
            #XXX it would be great if we could cancel the promise returned by
            #the look up.
            if (!$self->{_connecting}) { return };
    
            if ($err) {
                #net.createConnection() creates a net.Socket object and
                #immediately calls net.Socket.connect() on it (that's us).
                #There are no event listeners registered yet so defer the
                #error event to the next tick.
                Rum::process()->nextTick( sub {
                    $self->emit('error', $err);
                    $self->_destroy();
                });
            } else {
                Rum::Timers::_unrefActive($self);
                
                $addressType = $addressType || 4;
                
                #node_net.cc handles null host names graciously but user land
                #expects remoteAddress to have a meaningful value
                $ip = $ip || ($addressType == 4 ? '127.0.0.1' : '0:0:0:0:0:0:0:1');
                
                _connect($self,
                    $ip,
                    $options->{port},
                    $addressType,
                    $options->{localAddress},
                    $options->{localPort});
            }
        });
    }
    return $self;
}

sub isPipeName {
    my $s = shift;
    return 0;
    return $util->isString($s) && !Rum::Net::Server::toNumber($s);
}

sub afterConnect {
    my ($status, $handle, $req, $readable, $writable) = @_;
    my $self = $handle->{owner};
    
    #callback may come after call to destroy
    if ($self->{destroyed}) {
        return;
    }
    
    assert($handle == $self->{_handle}, 'handle != self._handle');
    
    debug('afterConnect');
    
    assert($self->{_connecting});
    $self->{_connecting} = 0;
    
    if ($status == 0) {
        $self->{readable} = $readable;
        $self->{writable} = $writable;
        Rum::Timers::_unrefActive($self);
        
        $self->emit('connect');
        
        #start the first read, or get an immediate EOF.
        #this doesn't actually consume any bytes, because len=0.
        if ($readable) {
            $self->read(0);
        }
        
    } else {
        $self->{_connecting} = 0;
        $self->_destroy(errnoException($status));
    }
}

sub end {
    my ($this, $data, $encoding) = @_;
    Rum::Stream::Duplex::end($this, $data, $encoding);
    $this->{writable} = 0;
    #DTRACE_NET_STREAM_END(this);

    #just in case we're waiting for an EOF.
    if ($this->{readable} && !$this->{_readableState}->{endEmitted}){
        $this->read(0);
    } else {
        maybeDestroy($this);
    }
}

sub _destroy {
    my ($this, $exception, $cb) = @_;
    debug('destroy');
    
    my $self = $this;
    
    #FIXME : this is a work around on error recieved
    #when forking a child process and the process exit immediately
    #instead of reporting an error we should just close the socket and
    #move on - applies to windows only
    if ($exception && CORE::ref $this->{_handle} eq 'Rum::Wrap::Pipe'){
        $exception = 0 if $exception == 10054; #WSAECONNRESET
    }
    
    my $fireErrorCallbacks = sub {
        if ($cb) {$cb->($exception)};
        if ($exception && !$self->{_writableState}->{errorEmitted}) {
            Rum::process()->nextTick( sub {
                $self->emit('error', $exception);
            });
            $self->{_writableState}->{errorEmitted} = 1;
        }
    };
    
    if ($self->{destroyed}) {
        debug('already destroyed, fire error callbacks');
        $fireErrorCallbacks->();
        return;
    }
  
    $self->{_connecting} = 0;
    
    $this->{readable} = $this->{writable} = 0;
    
    Rum::Timers::unenroll($this) if $this->{_idleTimeout};
    
    debug('close');
    if ($this->{_handle}) {
        #if ($this != Rum::process::stderr){
        #    debug('close handle');
        #}
        
        my $isException = $exception ? 1 : 0;
        $this->{_handle}->close( sub {
            debug('emit close');
            $self->emit('close', $isException);
        });
        $this->{_handle}->{onread} = sub{die};
        $this->{_handle} = undef;
    }
  
    #we set destroyed to true before firing error callbacks in order
    #to make it re-entrance safe in case Socket.prototype.destroy()
    #is called within callbacks
    $this->{destroyed} = 1;
    $fireErrorCallbacks->();
    
    if ($this->{server}) {
        debug('has server');
        $this->{server}->{_connections}--;
        if ($this->{server}->{_emitCloseIfDrained}) {
            $this->{server}->_emitCloseIfDrained();
        }
    }
}

sub ref {
    my $this = shift;
    if ($this->{_handle}) {
        $this->{_handle}->ref();
    }
}

1;

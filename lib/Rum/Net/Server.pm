package Rum::Net::Server;
use strict;
use warnings;
use lib '../../';
use Rum::Utils;
use Rum 'Require';
use base 'Rum::Events';
use Data::Dumper;
use Rum::Wrap::TCP;
use Rum::Net::Socket;
my $TCP_WRAP = 'Rum::Wrap::TCP';
my $util = 'Rum::Utils';

sub errnoException { &Rum::Utils::_errnoException }
sub setEncoding { &Rum::Stream::Readable::setEncoding }

sub debug {
    return;
    print STDERR "NET $$: ";
    for (@_){
        if (ref $_){
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
    my $this = ref $class ? $class : bless {}, $class;
    my $self = $this;
    
    my $options;
    
    if (ref $_[0] eq 'CODE') {
        $options = {};
        $self->on('connection', $_[0]);
    } else {
        $options = $_[0] || {};
        
        if (ref $_[1] eq 'CODE') {
            $self->on('connection', $_[1]);
        }
    }
    
    $this->{_connections} = 0;
    
    $this->{_handle} = undef;
    $this->{_usingSlaves} = 0;
    $this->{_slaves} = [];
    
    $this->{allowHalfOpen} = $options->{allowHalfOpen} || 0;
    return $this;
}

sub toNumber {
    my $x = shift;
    return ($util->isNumber($x) && $x >= 0) ? $x : undef;
}

sub isPipeName {
    my $s = shift;
    return $util->isString($s) && !defined toNumber($s);
}

sub listen {
    my $self = shift;
    
    my $lastArg = $_[-1];
    if ($util->isFunction($lastArg)) {
        $self->once('listening', $lastArg);
    }
    
    my $port = toNumber($_[0]);
    
    #The third optional argument is the backlog size.
    #When the ip is omitted it can be the second argument.
    my $backlog = toNumber($_[1]) || toNumber($_[2]);
    
    my $TCP;# = process->binding('tcp_wrap').TCP;
    
    if (@_ == 0 || $util->isFunction($_[0])) {
        #Bind to a random port.
        _listen($self, '0.0.0.0', 0, undef, $backlog);
        
    } elsif ( $_[0] && $util->isObject($_[0]) ) {
        my $h = $_[0];
        if ( $h->{_handle} ) {
            $h = $h->{_handle};
        } elsif ( $h->{handle} ) {
            $h = $h->{handle};
        }
        
        if (ref $h eq 'Rum::Wrap::TCP') {
            $self->{_handle} = $h;
            _listen($self, undef, -1, -1, $backlog);
        } elsif ($util->isNumber( $h->{fd} ) && $h->{fd} >= 0) {
            _listen( $self, undef, undef, undef, $backlog, $h->{fd} );
        } else {
            Rum::Error->new('Invalid listen argument: ' . Dumper $h)->throw();
        }
    } elsif ( isPipeName( $_[0]) ) {
        #UNIX socket or Windows pipe.
        my $pipeName = $self->{_pipeName} = $_[0];
        _listen($self, $pipeName, -1, -1, $backlog);
        
    } elsif ($util->isUndefined($_[1]) ||
             $util->isFunction($_[1]) ||
             $util->isNumber($_[1])) {
        #The first argument is the port, no IP given.
        _listen($self, '0.0.0.0', $port, 4, $backlog);
        
    } else {
        ##The first argument is the port, the second an IP.
        Require('dns')->lookup($_[1], sub {
            my ($err, $ip, $addressType) = @_;
            if ($err) {
                $self->emit('error', $err);
            } else {
                _listen($self, $ip || '0.0.0.0', $port, $ip ? $addressType : 4, $backlog);
            }
        });
    }
    return $self;
}

sub _listen {
    my ($self, $address, $port, $addressType, $backlog, $fd) = @_;
    $self->_listen2($address, $port, $addressType, $backlog, $fd);
    return;
}

sub _listen2 {
    my $self = shift;
    my ($address, $port, $addressType, $backlog, $fd) = @_;
    debug('listen2', $address, $port, $addressType, $backlog);
    
    my $alreadyListening = 0;
    
    #If there is not yet a handle, we need to create one and bind.
    #In the case of a server sent via IPC, we don't need to do this.
    if ( !$self->{_handle} ) {
        debug('_listen2: create a handle');
        my $rval = createServerHandle($address, $port, $addressType, $fd);
        if ( $util->isNumber($rval) ) {
            my $error = errnoException($rval, 'listen');
            Rum::Process->nextTick( sub {
                $self->emit('error', $error);
            });
            return;
        }
        #$alreadyListening = 1;
        $self->{_handle} = $rval;
    } else {
        debug('_listen2: have a handle already');
    }
    
    $self->{_handle}->{onconnection} = \&onconnection;
    $self->{_handle}->{owner} = $self;
    
    my $err = 0;
    if (!$alreadyListening){
        $err = __listen($self->{_handle}, $backlog);
    }
    
    if ($err) {
        my $ex = errnoException($err, 'listen');
        $self->{_handle}->close();
        undef $self->{_handle};
        Rum::Process->nextTick( sub {
            $self->emit('error', $ex);
        });
        return;
    }
    
    #generate connection key, this should be unique to the connection
    $self->{_connectionKey} = ($addressType || '') . ':' . ($address || 'undef') . ':' . ($port || '');
    
    Rum::Process->nextTick(sub {
        $self->emit('listening');
    });
}


sub __listen {
    my ($handle, $backlog) = @_;
    #Use a backlog of 512 entries. We pass 511 to the listen() call because
    #the kernel does: backlogsize = roundup_pow_of_two(backlogsize + 1);
    #which will thus give us a backlog of 512 entries.
    return $handle->listen($backlog || 511);
}

sub onconnection {
    
    my $handle = shift;
    my $self = $handle->{owner};
    
    debug('onconnection');
    
    my ($err, $clientHandle) = @_;
    
    if ($err) {
        $self->emit('error', errnoException($err, 'accept'));
        return;
    }
    
    if ($self->{maxConnections} && $self->{_connections} >= $self->{maxConnections} ) {
        $clientHandle->close();
        return;
    }
    
    my $socket = Rum::Net::Socket->new({
        handle => $clientHandle,
        allowHalfOpen => $self->{allowHalfOpen}
    });
    
    $socket->{readable} = $socket->{writable} = 1;
    
    $self->{_connections}++;
    $socket->{server} = $self;
    
    #DTRACE_NET_SERVER_CONNECTION(socket);
    #COUNTER_NET_SERVER_CONNECTION(socket);
    $self->emit('connection', $socket);
}

sub close {
    my ($this,$cb) = @_;
    my $left = 0;
    my $self = $this;
    my $onSlaveClose = sub {
        return if (--$left != 0);
        $self->{_connections} = 0;
        $self->_emitCloseIfDrained();
    };
    
    if (!$this->{_handle}) {
        #Throw error. Follows net_legacy behaviour.
        die('Not running');
    }
    
    if ($cb) {
        $this->once('close', $cb);
    }
    
    $this->{_handle}->close();
    undef $this->{_handle};
    
    if ($this->{_usingSlaves}) {
        $left = scalar @{$this->{_slaves}};
        
        #Increment connections to be sure that, even if all sockets will be closed
        #during polling of slaves, `close` event will be emitted only once.
        $this->{_connections}++;
        
        #Poll slaves
        foreach my $slave (@{$this->{_slaves}}){
            $slave->close($onSlaveClose);
        }
    } else {
        $this->_emitCloseIfDrained();
    }
    
    return $this;
}

sub _emitCloseIfDrained {
    my $self = shift;
    debug('SERVER _emitCloseIfDrained');
    if ($self->{_handle} || $self->{_connections}) {
        debug('SERVER handle? %j connections? %d',
            !!$self->{_handle}, $self->{_connections});
        return;
    }
    
    Rum::process()->nextTick(sub {
        debug('SERVER: emit close');
        $self->emit('close');
    });
}

sub createServerHandle {
    my ($address, $port, $addressType, $fd) = @_;
    my $err = 0;
    
    #assign handle in listen, and clean up if bind or listen fails
    my $handle;
    my $isTCP = 0;
    
    if ($util->isNumber($fd) && $fd >= 0) {
        die "not implemented";
    } elsif (($port && $port == -1) && ($addressType && $addressType == -1)) {
        $handle = createPipe();
    } else {
        $handle = createTCP();
        $isTCP = 1;
    }
    
    if ($address || $port || $isTCP) {
        debug('bind to ' . $address);
        if ($addressType == 6) {
            $err = $handle->bind6($address, $port);
        } else {
            $err = $handle->bind($address, $port);
        }
    }
    
    if ($err) {
        $handle->close();
        return $err;
    }
    
    if ($^O =~ /win32/i) {
        #On Windows, we always listen to the socket before sending it to
        #the worker (see uv_tcp_duplicate_socket). So we better do it here
        #so that we can handle any bind-time or listen-time errors early.
        $err = __listen($handle);
        if ($err) {
            $handle->close();
            return $err;
        }
    }
    
    return $handle;
}

sub createTCP {
    return $TCP_WRAP->new();
}

sub createPipe {
    return $TCP_WRAP->new();
}

sub _setupSlave {
    my ($this, $socketList) = @_;
    $this->{_usingSlaves} = 1;
    push @{$this->{_slaves}}, $socketList;
}

1;

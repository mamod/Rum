package Rum::HTTP::Agent;
use strict;
use warnings;
use Rum qw[Require exports module];
use base 'Rum::Events';
use Rum::HTTP::Common;
use Data::Dumper;

my $net = Require('net');
*createConnection = $net->{createConnection};
*debug = \&Rum::HTTP::Common::debug;

our $defaultMaxSockets = 99 * 99 * 99;

my $util = 'Rum::Utils';

sub new {
    my $this = shift;
    my $options = shift;
    
    my $self = bless {}, $this;
    
    Rum::Events::new($self);
    
    $self->{defaultPort} = 80;
    $self->{protocol} = 'http:';
    
    $self->{options} = $util->_extend({}, $options);
    
    #don't confuse net and make it think that we're connecting to a pipe
    $self->{options}->{path} = undef;
    $self->{requests} = {};
    $self->{sockets} = {};
    $self->{freeSockets} = {};
    $self->{keepAliveMsecs} = $self->{options}->{keepAliveMsecs} || 1000;
    $self->{keepAlive} = $self->{options}->{keepAlive} || 0;
    $self->{maxSockets} = $self->{options}->{maxSockets} || $defaultMaxSockets;
    $self->{maxFreeSockets} = $self->{options}->{maxFreeSockets} || 256;
    
    $self->on('free', sub {
        my ($this, $socket, $options) = @_;
        my $name = $self->getName($options);
        debug('agent.on(free)', $name);
        
        if (!$socket->{destroyed} &&
            $self->{requests}->{$name} && @{$self->{requests}->{$name}}) {
            my $sock = shift @{$self->{requests}->{$name}};
            $sock->onSocket($socket);
            if (@{$self->{requests}->{$name}} == 0) {
                # don't leak
                delete $self->{requests}->{$name};
            }
        } else {
            #If there are no pending requests, then put it in
            #the freeSockets pool, but only if we're allowed to do so.
            my $req = $socket->{_httpMessage};
            if ($req && $req->{shouldKeepAlive} &&
                !$socket->{destroyed} &&
                $self->{options}->{keepAlive}) {
                my $freeSockets = $self->{freeSockets}->{$name};
                my $freeLen = $freeSockets ? @{$freeSockets} : 0;
                my $count = $freeLen;
                if ($self->{sockets}->{$name}){
                    $count += @{$self->{sockets}->{$name}};
                }
                if ($count >= $self->{maxSockets} || $freeLen >= $self->{maxFreeSockets}) {
                    $self->removeSocket($socket, $options);
                    $socket->destroy();
                } else {
                    $freeSockets = $freeSockets || [];
                    $self->{freeSockets}->{$name} = $freeSockets;
                    $socket->setKeepAlive(1, $self->{keepAliveMsecs});
                    $socket->unref();
                    $socket->{_httpMessage} = undef;
                    $self->removeSocket($socket, $options);
                    push @{$freeSockets}, $socket;
                }
            } else {
                $self->removeSocket($socket, $options);
                $socket->destroy();
            }
        }
    });
    
    return $self;
}

sub addRequest {
    my ($this, $req, $options) = @_;
    # Legacy API: addRequest(req, host, port, path)
    if ($util->isString($options)) {
        $options = {
            host => $options,
            port => $_[3],
            path => $_[4]
        };
    }
    
    my $name = $this->getName($options);
    if (!$this->{sockets}->{$name}) {
        $this->{sockets}->{$name} = [];
    }
    
    my $freeLen = $this->{freeSockets}->{$name} ? @{$this->{freeSockets}->{$name}} : 0;
    my $sockLen = $freeLen + @{$this->{sockets}->{$name}};

    if ($freeLen) {
        # we have a free socket, so use that.
        my $socket = shift @{$this->{freeSockets}->{$name}};
        debug('have free socket');
        
        # don't leak
        if (!@{$this->{freeSockets}->{$name}}) {
            delete $this->{freeSockets}->{$name};
        }
        
        $socket->ref();
        $req->onSocket($socket);
        push @{$this->{sockets}->{$name}}, $socket;
    } elsif ($sockLen < $this->{maxSockets}) {
        debug('call onSocket', $sockLen, $freeLen);
        # If we are under maxSockets create a new one.
        $req->onSocket($this->createSocket($req, $options));
    } else {
        debug('wait for socket');
        # We are over limit so we'll add it to the queue.
        if (!$this->{requests}->{$name}) {
            $this->{requests}->{$name} = [];
        }
        push @{$this->{requests}->{$name}}, $req;
    }
}

sub getName {
    my ($this, $options) = @_;
    my $name = '';
    
    if ($options->{host}) {
        $name .= $options->{host};
    } else {
        $name .= 'localhost';
    }
    
    $name .= ':';
    
    if ($options->{port}) {
        $name .= $options->{port};
    }
    
    $name .= ':';
    
    if ($options->{localAddress}) {
        $name .= $options->{localAddress};
    }
    $name .= ':';
    return $name;
}

sub createSocket {
    my ($this, $req, $options) = @_;
    my $self = $this;
    $options = $util->_extend({}, $options);
    $options = $util->_extend($options, $self->{options});
    
    $options->{servername} = $options->{host};
    if ($req) {
        my $hostHeader = $req->getHeader('host');
        if ($hostHeader) {
            $hostHeader =~ s/:.*$//;
            $options->{servername} = $hostHeader;
        }
    }

    my $name = $self->getName($options);
    
    debug('createConnection', $name, $options);
    $options->{encoding} = undef;
    my $s = $self->createConnection($options);
    if (!$self->{sockets}->{$name}) {
        $self->{sockets}->{$name} = [];
    }
    push @{$this->{sockets}->{$name}}, $s;
    debug('sockets', $name, scalar @{$this->{sockets}->{$name}});
    
    my $onFree = sub {
        $self->emit('free', $s, $options);
    };
    
    $s->on('free', $onFree);
    
    my $onClose = sub {
        debug('CLIENT socket onClose');
        # This is the only place where sockets get removed from the Agent.
        # If you want to remove a socket from the pool, just close it.
        # All socket errors end in a close event anyway.
        $self->removeSocket($s, $options);
    };
    
    $s->on('close', $onClose);
    
    my $onRemove; $onRemove = sub {
        #We need this function for cases like HTTP 'upgrade'
        #(defined by WebSockets) where we need to remove a socket from the
        #pool because it'll be locked up indefinitely
        debug('CLIENT socket onRemove');
        $self->removeSocket($s, $options);
        $s->removeListener('close', $onClose);
        $s->removeListener('free', $onFree);
        $s->removeListener('agentRemove', $onRemove);
    };
    $s->on('agentRemove', $onRemove);
    return $s;
}

sub globalAgent {
    return __PACKAGE__->new();
}


sub _indexOf {
    my $list = shift;
    my $test = shift;
    
    my $i = 0;
    foreach my $val (@{$list}){
        if ($val == $test) {
            return $i;
        }
        
        $i++;
    }
    
    return -1;
}

sub removeSocket {
    my ($this, $s, $options) = @_;
    my $name = $this->getName($options);
    debug('removeSocket', $name, 'destroyed:', $s->{destroyed});
    my $sets = [$this->{sockets}];
    
    #If the socket was destroyed, remove it from the free buffers too.
    if ($s->{destroyed}) {
        push @{$sets}, $this->{freeSockets};
    }
    
    foreach my $sockets (@{$sets}) {
        if ($sockets->{$name}) {
            my $index = _indexOf($sockets->{$name}, $s);
            if ($index != -1) {
                splice @{$sockets->{$name}}, $index, 1;
                #Don't leak
                if (!@{$sockets->{$name}}) {
                    delete $sockets->{$name};
                }
            }
        }
    }
    
    if ($this->{requests}->{$name} && @{$this->{requests}->{$name}}) {
        debug('removeSocket, have a request, make a socket');
        my $req = $this->{requests}->{$name}->[0];
        #If we have pending requests and a socket gets closed make a new one
        $this->createSocket($req, $options)->emit('free');
    }
}

our $globalAgent = exports->{globalAgent} = globalAgent();

1;

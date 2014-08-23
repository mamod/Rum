package Rum::Events;
use Rum::Utils;
use strict;
use warnings;
use Carp;
use Scalar::Util 'weaken';
use Data::Dumper;
our $defaultMaxListeners = 10;
my $Utils = Rum::Utils->new();
our $usingDomains = 0;
our $domain;

sub new {
    my $class = shift;
    my $this = ref $class ? $class : bless {},'Rum::Events';
    $this->{domain} = undef;
    if ($usingDomains) {
        #if there is an active domain, then attach to it.
        $domain = $domain || Require('domain');
        #if ($domain->{active} && !(this instanceof domain.Domain)) {
        #    $this->{domain} = $domain->{active};
        #}
    }
    
    $this->{_events} ||= {};
    $this->{_maxListeners} ||= undef;
    return $this;
}

sub trace {}
sub addListener {
    my ($this, $type, $listener) = @_;
    my $m;
    
    my $listenerType = ref $listener;
    if ($listenerType ne 'CODE' && $listenerType ne 'Rum::Events::Once') {
        Carp::croak('listener must be a function');
    }
    
    if ( !$this->{_events} ) {
        $this->{_events} = {};
    }

    #To avoid recursion in the case that type === "newListener"! Before
    #adding it to the listeners, first emit "newListener".
    if ( $this->{_events}->{newListener} ) {
        $this->emit('newListener', $type,
            $listenerType eq 'Rum::Events::Once' ?
            $listener->{listener} : $listener);
    }
    
    ## my $event = $this->{_events}->{$type};
    
    if (!$this->{_events}->{$type}) {
        #Optimize the case of one listener.
        #Don't need the extra array object.
        $this->{_events}->{$type} = $listener;
    } elsif (ref $this->{_events}->{$type} eq 'ARRAY') {
        #If we've already got an array, just append.
        push @{ $this->{_events}->{$type} },$listener;
    } else {
        #Adding the second element, need to change to array.
        $this->{_events}->{$type} = [$this->{_events}->{$type}, $listener];
    }
    
    #Check for listener leak
    if (ref $this->{_events}->{$type} eq 'ARRAY' && !$this->{_events_warned}->{$type} ) {
        my $m;
        if ( defined $this->{_maxListeners} ) {
            $m = $this->{_maxListeners};
        } else {
            $m = $Rum::Events::defaultMaxListeners;
        }
        
        my $length = @{ $this->{_events}->{$type} };
        if ( $m && $m > 0 && $length > $m) {
            $this->{_events_warned}->{$type} = 1;
            warn('(Rum) warning: possible EventEmitter memory ' .
                    "leak detected. $length listeners added. " .
                    'Use $emitter->setMaxListeners() to increase limit.');
            
            ##TODO - trace warning loation
            trace();
        }
    }

    return $this;
}

sub on {&addListener}

sub once  {
    #return &on;
    my ($this, $type, $listener) = @_;
    if (ref $listener ne 'CODE' ) {
        Carp::croak('listener must be a function');
    }
    my $fired = 0;
    weaken $this;
    my $obj = bless {}, 'Rum::Events::Once';
    $obj->{do} = sub {
        $this->removeListener($type,$obj);
        if (!$fired) {
            $fired = 1;
            $listener->(@_);
        }
    };
    
    $obj->{listener} = $listener;
    $this->on($type, $obj);
    weaken $obj;
    return $this;
}

#emits a 'removeListener' event if the listener was removed
sub removeListener  {
    my ($this, $type, $listener) = @_;
    my ($list, $position, $length, $i,$ref);
    
    if (ref $listener ne 'CODE' && ref $listener ne 'Rum::Events::Once') {
        Carp::croak('listener must be a function');
    }
    
    return $this if (!$this->{_events} || !$this->{_events}->{$type});
    
    $list = $this->{_events}->{$type};
    $ref = ref $list;
    $length = ref $this->{_events}->{$type} eq 'ARRAY' ?  scalar @{$list} : 0;
    $position = -1;
    
    if ($ref eq 'ARRAY') {
        for ($i = $length; $i-- > 0;) {
            if ($list->[$i] == $listener ||
              ( ref $list->[$i] eq 'HASH'
                && $list->[$i]->{listener}
                && $list->[$i]->{listener} == $listener) ) {
                $position = $i;
                last;
            }
        }
        
        if ($position < 0){
          return $this;
        }
        
        if (scalar @{$list} == 1) {
            delete $this->{_events}->{$type};
            #delete this._events[type];
            #$this->{_events}->{$type} = [];
        } else {
            splice @{$list}, $position, 1;
        }
        
        if ( $this->{_events}->{removeListener} ){
          $this->emit('removeListener', $type, $listener);
        }
        
    } elsif ($list == $listener ||
      ( $ref
        && ref $list->{listener} eq 'CODE'
        && $list->{listener} == $listener) ) {
        delete $this->{_events}->{$type};
        if ($this->{_events}->{removeListener}){
            $this->emit('removeListener', $type, $listener);
        }
    }
    
    return $this;
}


sub emit  {
    my ($this,$type) = (shift,shift);
    my ($er, $handler, $len, $args, $i, $listeners);
    if (!$this->{_events}) {
        $this->{_events} = {};
    }
    
    my $domain = $Utils->hasDomain($this);
    #If there is no 'error' event listener then throw.
    if ($type eq 'error') {
        my $errorEvent = $this->{_events}->{error};
        if (!$errorEvent ||
            (ref $errorEvent eq 'ARRAY' && scalar @{$errorEvent} == 0)) {
            $er = $_[0];
            if ($domain) {
                $er = Rum::Error->new('Uncaught, unspecified "error" event.') if (!$er);
                $er->{domainEmitter} = $this;
                $er->{domain} = $domain;
                $er->{domainThrown} = 0;
                $domain->emit('error', $er);
            } elsif (ref $er eq 'Rum::Error') {
                $er->throw; # Unhandled 'error' event
            } else {
                #croak $er;
                Carp::croak('Uncaught, unspecified "error" event.');
            }
            return 0;
        }
    }

    $handler = $this->{_events}->{$type};

    if ( !defined $handler ) {
        return;
    }

    if ($domain && ref $this ne 'Rum::Process'){
        $domain->enter();
    }
    
    my @args = ($this,@_);
    
    if (ref $handler eq 'CODE' || ref $handler eq 'Rum::Events::Once') {
        $handler->(@args);
    } elsif (ref $handler eq 'ARRAY') {
        my @listners = @{$handler}[0.. (@{$handler} - 1)];
        foreach my $listner (@listners){
            $listner->(@args);
        }
    }
    if ($domain && ref $this ne 'Rum::Process') {
        $domain->exit();
    }

    return 1;
}

sub removeAllListeners {
    my $this = shift;
    my ($type) = @_;
    my ($key, $listeners);

    if (!$this->{_events}){
        return $this;
    }
    
    #not listening for removeListener, no need to emit
    if (!$this->{_events}->{removeListener}) {
        if (!@_) {
            $this->{_events} = {};
        } elsif ($this->{_events}->{$type}) {
            delete $this->{_events}->{$type};
        }
        return $this;
    }

    #emit removeListener for all listeners on all events
    if (!@_) {
        foreach my $key (keys %{ $this->{_events} }) {
            next if ($key eq 'removeListener');
            $this->removeAllListeners($key);
        }
        $this->removeAllListeners('removeListener');
        $this->{_events} = {};
        return $this;
    }

    $listeners = $this->{_events}->{$type};
    
    my $ref = ref $listeners;
    if ($ref eq 'CODE') {
        $this->removeListener($type, $listeners);
    } elsif (ref $listeners eq 'ARRAY')  {
        #LIFO order
        while ( 1 ) {
            my $length = @{$listeners}-1;
            $this->removeListener($type, $listeners->[$length]);
            last if !$length;
        }
    } else {
        ##something wrong a bug maybe
        die $ref;
    }
    
    delete $this->{_events}->{$type};
    return $this;
}

sub setMaxListeners {
    my ($this,$n) = @_;
    if (!$Utils->isNumber($n) || $n < 0) {
        Carp::croak('n must be a positive number');
    }
    $this->{_maxListeners} = $n;
    return $this;
}

sub listeners {
    my ($this,$type) = @_;
    my @ret;
    my $listeners = $this->{_events}
    ? $this->{_events}->{$type}
    : undef;
    
    if (!$listeners){
        @ret = ();
    } elsif (ref $listeners eq 'CODE'){
        @ret = ($listeners);
    } else {
        @ret = @{$listeners}[0 .. @{$listeners} - 1];
    }
    
    return wantarray ? @ret : \@ret;
}

sub listenerCount {
    my ($emitter, $type) = @_;
    my $listeners = $emitter->{_events}
    ? $emitter->{_events}->{$type}
    : undef;
    
    if (!$listeners) {
        return 0;
    } elsif (ref $listeners eq 'CODE') {
        return 1;
    }
    return scalar @{ $listeners };
}

package Rum::Events::Once; {
    use warnings;
    use strict;
    use Data::Dumper;
    use overload '&{}' => sub{
        my $self = shift;
        return sub{ $self->{do}->(@_) }
    }, fallback => 1;
    
    sub new {bless {}, __PACKAGE__}
}

1;

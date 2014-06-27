package Rum::Timers;
use strict;
use warnings;
use Rum::TryCatch;

use Time::HiRes 'time';
use constant TIMEOUT_MAX => 2147483647; # 2^31-1
use base qw/Exporter/;
our @EXPORT = qw (
    setTimeout
    setInterval
    clearInterval
    clearTimeout
    start_timers
);

my $lists = {};
my $L = Rum::Timers::LinkedLists->new();

sub now { int( time() * 1000 ) }

##this function will be replaced when using Rum
##for running rum applications see Rum.pm
sub MakeCallback {
    my ($obj,$name) = @_;
    $obj->{$name}->($obj);
}

sub debug {
    #print $_[0] . "\n";
}
#=============================================================================================
# Set Timers
#=============================================================================================
sub setTimeout {
    my ($callback, $after, @args) = @_;
    $after += 0;
    if (!($after >= 1 && $after <= TIMEOUT_MAX)) {
        $after = 1; #schedule on next tick, follows browser behaviour
    }
    
    my $timer = Rum::Timers::Timeout->new($after);
    $timer->{_onTimeout} = sub {
        $callback->($timer,@args);
    };
    
    active($timer);
    return $timer;
}

sub setInterval  {
    my ($callback, $repeat,@args) = @_;
    my $timer = Rum::Timers::Timer->new();
    $repeat += 0;
    if (!($repeat >= 1 && $repeat <= TIMEOUT_MAX)) {
        $repeat = 1; #schedule on next tick, follows browser behaviour
    }
    
    $timer->{ontimeout} = sub {
        $callback->($timer,@args);
    };
    
    $timer->start($repeat, $repeat);
    return $timer;
}

#=============================================================================================
# clearTimers
#=============================================================================================
sub clearInterval {
    my ($timer) = @_;
    if (ref $timer eq 'Rum::Timers::Timer') {
        $timer->{ontimeout} = undef;
        $timer->close();
    }
}

sub clearTimeout {
    my ($timer) = @_;
    if ($timer && ( $timer->{ontimeout} || $timer->{_onTimeout} )) {
        $timer->{ontimeout} = $timer->{_onTimeout} = undef;
        if (ref $timer eq 'Rum::Timers::Timer' || ref $timer eq 'Rum::Timers::Timeout') {
            $timer->close();
        } else {
            $timer->unenroll();
        }
    }
}

#=============================================================================================
# active
#=============================================================================================
# call this whenever the item is active (not idle)
# it will reset its timeout.
#=============================================================================================
sub active  {
    my ($item) = @_;
    my $msecs = $item->{_idleTimeout};
    if ($msecs >= 0) {
        my $list = $lists->{$msecs};
        if (!$list || $L->isEmpty($list)) {
            insert($item, $msecs);
        } else {
            $item->{_idleStart} = Rum::Timers::now();
            $L->append($list, $item);
        }
    }
}

sub insert {
    my ($item, $msecs) = @_;
    $item->{_idleStart} = Rum::Timers::now();
    $item->{_idleTimeout} = $msecs;
    return if ($msecs < 0);
    my $list;
    if ($lists->{$msecs}) {
        $list = $lists->{$msecs};
    } else {
        $list = Rum::Timers::Timer->new();
        $list->start($msecs, 0);
        $L->init($list);
        $list->{msecs} = $msecs;
        $list->{ontimeout} = \&listOnTimeout;
        $lists->{$msecs} = $list;
    }

    $L->append($list, $item);
}

sub listOnTimeout {
    my ($this) = @_;
    my $msecs = $this->{msecs};
    my $list = $this;
    my $now = Rum::Timers::now();
    my $first;
    while ( $first = $L->peek($list) ) {
        my $diff = $now - $first->{_idleStart};
        if ($diff < ($msecs)) {
            $list->start($msecs - $diff, 0);
            debug($msecs . ' list wait because diff is ' . $diff);
            return;
        } else {
            $L->remove($first);
            next if !$first->{_onTimeout};
            
            my $domain = $first->{domain};
            next if ($domain && $domain->{_disposed});
            
            my $threw = 1;
            try {
                $domain->enter() if $domain;
                $first->{_onTimeout}->();
                $domain->exit() if $domain;
                $threw = 0;
            } finally {
                if ($threw) {
                    process->nextTick( sub {
                        $this->{ontimeout}->();
                    });
                }
            };
        }
    }
    
    debug("$msecs list empty");
    $list->close();
    delete $lists->{msecs};
}

sub start_timers { Rum::Timers::Timer::run_timers() }

#=============================================================================================
# Timer Package
#=============================================================================================
package Rum::Timers::Timer; {
    use strict;
    use warnings;
    use Tree::RB;
    use Time::HiRes 'time';
    my $timer_counter = 0;
    my $tree = Tree::RB->new(\&timer_cmp);

    sub timer_cmp {
        my ($a,$b) = @_;
        return -1 if ($a->{timeout} < $b->{timeout});
        return  1 if ($a->{timeout} > $b->{timeout});
        #compare start_id when both has the same timeout
        return -1 if ($a->{start_id} < $b->{start_id});
        return  1 if ($a->{start_id} > $b->{start_id});
        return 0;
    }

    sub new {
        bless {
            _handle => {}
        }, shift;
    }

    sub OnTimeout {
        my ($handle, $status) = @_;
        my $wrap = $handle->{wrap};
        Rum::Timers::MakeCallback($wrap,'ontimeout');
    }

    sub start {
        my ($this,$timeout,$repeat) = @_;
        my $handle = $this->{_handle};
        $handle->{wrap} = $this;
        timer_start($handle, \&OnTimeout, $timeout, $repeat);
    }

    sub timer_start {
        my ($handle,$cb,$timeout,$repeat) = @_;
        timer_stop($handle) if $handle->{active};
        $handle->{active} = 1;
        my $clamped_timeout = Rum::Timers::now() + $timeout;
        $clamped_timeout = -1 if ($clamped_timeout < $timeout);
        
        $handle->{timer_cb} = $cb;
        $handle->{timeout} = $clamped_timeout;
        $handle->{repeat} = $repeat;
        
        # start_id is the second index to be compared in uv__timer_cmp()
        $handle->{start_id} = $timer_counter++;
        $tree->put($handle);
    }

    sub close {
        my ($self) = @_;
        $self->{_handle}->{stop} = 1;
        timer_stop($self->{_handle});
    }

    sub run_timers {
        while(my $node = $tree->min) {
            my $handle = $node->key;
            select(undef,undef,undef,.001);
            if ($handle->{timeout} > Rum::Timers::now()+10 ) {
                next;
            }
            timer_stop($handle);
            timer_again($handle);
            $handle->{timer_cb}->($handle,0);
        }
    }
    
    ##run single ready timer
    sub run_timer {
        if (my $node = $tree->min) {
            my $handle = $node->key;
            if ($handle->{timeout} > $_[0] ) {
                return 1;
            };
            timer_stop($handle);
            timer_again($handle);
            $handle->{timer_cb}->($handle,0);
            return 1;
        }
        return 0;
    }

    sub timer_stop {
        my ($handle) = @_;
        #undef $handle;
        $tree->delete($handle);
        $handle->{active} = 0;
    }

    sub timer_again {
        my ($handle) = @_;
        if (!$handle->{timer_cb}) { die('TIMER ERROR') };
        if ($handle->{repeat}) {
            #timer_stop($handle);
            timer_start($handle, $handle->{timer_cb}, $handle->{repeat}, $handle->{repeat});
        }
    }
}

#=============================================================================================
# Timeout Package
#=============================================================================================
package Rum::Timers::Timeout; {
    use strict;
    use warnings;
    sub new {
        my $class = shift;
        my $after = shift;
        my $this = bless {}, $class;
        $this->{_idleTimeout} = $after;
        $this->{_idlePrev}    = $this;
        $this->{_idleNext}    = $this;
        $this->{_idleStart}   = undef;
        $this->{_onTimeout}   = undef;
        return $this;
    }

    sub close {
        my $this = shift;
        $this->{_onTimeout} = undef;
        if ($this->{_handle}) {
            $this->{_handle}->{ontimeout} = undef;
            $this->{_handle}->close();
        } else {
            $this->unenroll();
        }
    }

    sub unenroll {
        my $item = shift;
        $L->remove($item);
        my $list = $lists->{ $item->{_idleTimeout} };
        #if empty then stop the watcher
        Rum::Timers::debug('unenroll');
        if ( $list && $L->isEmpty($list) ) {
            Rum::Timers::debug('unenroll: list empty');
            $list->close();
            delete $lists->{ $item->{_idleTimeout} };
        }
        #if active is called later, then we want to make sure not to insert again
        $item->{_idleTimeout} = -1;
    }
}

#=============================================================================================
# Linkedlists Package
#=============================================================================================
package Rum::Timers::LinkedLists; {
    use strict;
    use warnings;
    sub new {
        bless {}, shift; 
    }

    sub init {
        my ($self,$list) = @_;
        $list->{_idleNext} = $list;
        $list->{_idlePrev} = $list;
    }

    sub append {
        my ($self,$list, $item) = @_;
        $self->remove($item);
        $item->{_idleNext} = $list->{_idleNext};
        $list->{_idleNext}->{_idlePrev} = $item;
        $item->{_idlePrev} = $list;
        $list->{_idleNext} = $item;
    }

    #remove the most idle item from the list
    sub shift  {
        my ($self,$list) = @_;
        my $first = $list->{_idlePrev};
        $self->remove($first);
        return $first;
    }

    sub remove {
        my ($self,$item) = @_;
        if ($item->{_idleNext}) {
            $item->{_idleNext}->{_idlePrev} = $item->{_idlePrev};
        }
        if ($item->{_idlePrev}) {
            $item->{_idlePrev}->{_idleNext} = $item->{_idleNext};
        }
        $item->{_idleNext} = undef;
        $item->{_idlePrev} = undef;
    }

    sub isEmpty {
        my ($self,$list) = @_;
        return $list == $list->{_idleNext};
    }

    sub peek {
        my ($self,$list) = @_;
        return undef if $list->{_idlePrev} && $list->{_idlePrev} == $list;
        return $list->{_idlePrev};
    }
}

1;

__END__

=head1 NAME

Rum::Timers - Javascript timeout methods

=head1 SYNOPSIS

    use Rum::Timers;
    ##or just export what you need
    use Rum::Timers qw(setTimeout clearTimeout);
    
    my $timout = setTimeout(sub{
        say 'Hi';
    },100);
    
    clearTimeout($timeout);
    
    Rum::Timers::start_timers();

=head1 DESCRIPTION

Rum::Timers implements Javascript's timeouts, it was designed to be used with Rum applications but can be used
as a stand alone module too, it's a direct port from nodejs timers and has been tested with hundreds of timers running
at the same time and gave a very good results, in some cases - comparing - to nodejs it showed better memory usage and faster
responses

=head1 METHODS

=head2 setTimeout

    setTimeout( coderef,milliseconds, @args );

Excute coderef once after milliseconds passed, timeout must be in milliseconds  1000 = 1 second,
you can pass extra args to your code ref

    setTimeout({
        print "My Name is " $_[0] . " " . $_[1];
    }, 1000, 'Joe', 'Due');

=head2 setInterval

    setTimeout( coderef,timeout, @args );

Same as setTimeout but excutes coderef at milliseconds intervals until you call clearInterval

    my $i = 0;
    my $timer;$timer = setInterval(sub{
        clearInterval($timer) if $i >= 100;
        print $i++;
    },100);

=head2 clearTimeout

    clearTimeout($timeout);

=head2 clearInterval

    clearInterval($timeout);

=head2 start_timer

Should be called at the end of your program execution process to start timers

    start_timers();

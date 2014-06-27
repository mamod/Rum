package Rum::Timers;
use strict;
use warnings;
use Rum::TryCatch;
use Rum::LinkedLists;
use Rum::Wrap::Timers;
use Rum::Loop::Utils 'assert';
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
use Data::Dumper;

my $lists = {};
my $immediateQueue = {};
my $L = Rum::LinkedLists->new();

sub now { &Rum::Wrap::Timers::now }

##this function will be replaced when using Rum
##for running rum applications see Rum.pm
sub MakeCallback {
    my ($obj,$name) = @_;
    $obj->{$name}->($obj);
}

sub debug {
    return;
    print "TIMER $$: ";
    for (@_){
        if (ref $_){
            print Dumper $_;
        } elsif (defined $_) {
            print $_ . " ";
        } else {
            print "undefined ";
        }
    }
    print STDERR "\n";
}

sub process {
    return Rum::process();
}

#=============================================================================================
# the main function - creates lists on demand and the watchers associated
# with them.
#=============================================================================================
sub insert {
    my ($item, $msecs) = @_;
    $item->{_idleStart} = Rum::Timers::now();
    $item->{_idleTimeout} = $msecs;
    return if ($msecs < 0);
    my $list;
    if ($lists->{$msecs}) {
        $list = $lists->{$msecs};
    } else {
        $list = Rum::Wrap::Timers->new();
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
    
    debug("timeout callback $msecs");
    
    my $now = Rum::Timers::now();
    debug("now: $now");
    
    my $first;
    while ( $first = $L->peek($list) ) {
        my $diff = $now - $first->{_idleStart};
        if ($diff < $msecs) {
            $list->start($msecs - $diff, 0);
            debug($msecs . ' list wait because diff is ' . $diff);
            return;
        } else {
            $L->remove($first);
            
            #die if ($first eq $L->peek($list));
            
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
                    Rum::process()->nextTick( sub {
                        $this->{ontimeout}->();
                    });
                    die @_;
                }
            };
        }
    }
    
    debug("$msecs list empty");
    $list->close();
    delete $lists->{$msecs};
}

sub unenroll {
    my ($item) = @_;
    $L->remove($item);
    return if !$item->{_idleTimeout};
    my $list = $lists->{$item->{_idleTimeout}};
    #if empty then stop the watcher
    debug('unenroll');
    if ($list && $L->isEmpty($list)) {
        debug('unenroll: list empty');
        $list->close();
        delete $lists->{ $item->{_idleTimeout} };
    }
    #if active is called later, then we want to make sure not to insert again
    $item->{_idleTimeout} = -1;
}

#Does not start the time, just sets up the members needed.
sub enroll {
    my ($item, $msecs) = @_;
    #if this item was already in a list somewhere
    #then we should unenroll it from that
    unenroll($item) if $item->{_idleNext};

    #Ensure that msecs fits into signed int32
    if ($msecs > 0x7fffffff) {
        $msecs = 0x7fffffff;
    }
    
    $item->{_idleTimeout} = $msecs;
    $L->init($item);
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

#=============================================================================================
# Timeout
#=============================================================================================
sub setTimeout {
    my ($callback, $after, @args) = @_;
    $after += 0;
    if (!($after >= 1 && $after <= TIMEOUT_MAX)) {
        $after = 1; #schedule on next tick, follows browser behaviour
    }
    
    my $timer = Rum::Timers::Timeout->new($after);
    
    #if (process.domain) timer.domain = process.domain;
    
    $timer->{_onTimeout} = sub {
        $callback->($timer,@args);
    };
    
    active($timer);
    return $timer;
}

sub clearTimeout {
    my ($timer) = @_;
    if ($timer && ( $timer->{ontimeout} || $timer->{_onTimeout} )) {
        $timer->{ontimeout} = $timer->{_onTimeout} = undef;
        if (ref $timer eq 'Rum::Timers::Timeout') {
            $timer->close();
        } else {
            unenroll($timer);
        }
    }
}

#=============================================================================================
# Interval
#=============================================================================================
sub setInterval {
    my ($callback, $repeat, @args) = @_;
    $repeat += 0; # coalesce to number or NaN
    
    if (!($repeat >= 1 && $repeat <= TIMEOUT_MAX)) {
        $repeat = 1; #schedule on next tick, follows browser behaviour
    }
    
    my $timer = Rum::Timers::Timeout->new($repeat);
    
    my $wrapper = sub {
        $callback->($timer, @args);
        #If callback called clearInterval().
        return if !$timer->{_repeat};
        #If timer is unref'd (or was - it's permanently removed from the list.)
        if ($timer->{_handle}) {
            $timer->{_handle}->start($repeat, 0);
        } else {
            $timer->{_idleTimeout} = $repeat;
            active($timer);
        }
    };
    
    $timer->{_onTimeout} = $wrapper;
    $timer->{_repeat} = 1;

    #if (process.domain) timer.domain = process.domain;
    active($timer);
    return $timer;
}

sub clearInterval {
    my ($timer) = @_;
    if ($timer && $timer->{_repeat}) {
        $timer->{_repeat} = 0;
        clearTimeout($timer);
    }
}

#=============================================================================================
# Immediate
#=============================================================================================
sub setImmediate {
    my $callback = shift;
    my $immediate = Rum::Timers::Immediate->new();
    my (@args, $index);
    
    $L->init($immediate);
    $immediate->{_onImmediate} = $callback;
    
    if (@_ > 1) {
        @args = ();
        for ($index = 1; $index < @_; $index++){
            push @args, $_[$index];
        }
    
        $immediate->{_onImmediate} = sub {
            $callback->($immediate, @args);
        };
    }
    
    if ( !process->_needImmediateCallback() ) {
        process->_needImmediateCallbackSetter(1);
        process->{_immediateCallback} = \&processImmediate;
    }
    
    #setImmediates are handled more like nextTicks.
    #if ($asyncFlags[kHasListener] > 0) {
    #    runAsyncQueue($immediate);
    #}
    
    if (process->{domain}) {
        $immediate->{domain} = process->{domain};
    }
    
    $L->append($immediateQueue, $immediate);
    
    return $immediate;
}


sub processImmediate {
    my $queue = $immediateQueue;
    my ($domain, $hasQueue, $immediate);
    
    $immediateQueue = {};
    $L->init($immediateQueue);
    
    while (!$L->isEmpty($queue) ) {
        $immediate = $L->shift($queue);
        $hasQueue = !!$immediate->{_asyncQueue};
        $domain = $immediate->{domain};
        
        die;
        if ($hasQueue) {
            loadAsyncQueue($immediate);
        }
        
        if ($domain) {
            $domain->enter();
        }
        
        my $threw = 1;
        try {
            $immediate->{_onImmediate}->();
            $threw = 0;
        } finally {
            if ($threw) {
                if (!$L->isEmpty($queue)) {
                    #Handle any remaining on next tick, assuming we're still
                    #alive to do so.
                    while (!$L->isEmpty($immediateQueue)) {
                        $L->append($queue, $L->shift($immediateQueue));
                    }
                    $immediateQueue = $queue;
                    process->nextTick(\&processImmediate);
                }
            }
        };
        
        if ($domain) {
            $domain->exit();
        }
        if ($hasQueue) {
            unloadAsyncQueue($immediate);
        }
    }

    #Only round-trip to C++ land if we have to. Calling clearImmediate() on an
    #immediate that's in |queue| is okay. Worst case is we make a superfluous
    #call to NeedImmediateCallbackSetter().
    if ($L->isEmpty($immediateQueue)) {
        process->_needImmediateCallbackSetter(0);
    }
}

my ($unrefList, $unrefTimer);

sub unrefTimeout {
    my $now = Rum::Timers::now();
    
    debug('unrefTimer fired');
    
    my ($diff, $domain, $first, $hasQueue, $threw);
    while ($first = $L->peek($unrefList)) {
        
        $diff = $now - $first->{_idleStart};
        
        if ($diff < $first->{_idleTimeout}) {
            $diff = $first->{_idleTimeout} - $diff;
            $unrefTimer->start($diff, 0);
            $unrefTimer->{when} = $now + $diff;
            debug('unrefTimer rescheudling for later');
            return;
        }
        
        $L->remove($first);
        
        $domain = $first->{domain};
        
        if (!$first->{_onTimeout}) { next };
        if ($domain && $domain->{_disposed}) { next };
        $hasQueue = !!$first->{_asyncQueue};
        
        try {
            if ($hasQueue) {
                loadAsyncQueue($first);
            }
            
            if ($domain) { $domain->enter() };
            $threw = 1;
            debug('unreftimer firing timeout');
            $first->_onTimeout();
            $threw = 0;
            if ($domain) {
                $domain->exit();
            }
            
            if ($hasQueue){
                unloadAsyncQueue($first);
            }
            
        } finally {
            if ($threw) { Rum::process()->nextTick(\&unrefTimeout) };
        };
    }

    debug('unrefList is empty');
    $unrefTimer->{when} = -1;
}



sub _unrefActive {
    
    my $item = shift;
    my $msecs = $item->{_idleTimeout};
    if (!$msecs || $msecs < 0) {return};
    assert($msecs >= 0);

    $L->remove($item);

    if (!$unrefList) {
        debug('unrefList initialized');
        $unrefList = {};
        $L->init($unrefList);
        
        debug('unrefTimer initialized');
        $unrefTimer = Rum::Wrap::Timers->new();
        $unrefTimer->unref();
        $unrefTimer->{when} = -1;
        $unrefTimer->{ontimeout} = \&unrefTimeout;
    }
    
    my $now = Rum::Timers::now();
    $item->{_idleStart} = $now;
    
    if ($L->isEmpty($unrefList)) {
        debug('unrefList empty');
        $L->append($unrefList, $item);
        
        $unrefTimer->start($msecs, 0);
        $unrefTimer->{when} = $now + $msecs;
        debug('unrefTimer scheduled');
        return;
    }

    my $when = $now + $msecs;
    
    debug('unrefList find where we can insert');
    
    my ($cur, $them);

    for ($cur = $unrefList->{_idlePrev}; $cur != $unrefList; $cur = $cur->{_idlePrev}) {
        $them = $cur->{_idleStart} + $cur->{_idleTimeout};
        
        if ($when < $them) {
            debug('unrefList inserting into middle of list');
            
            $L->append($cur, $item);
            
            if ($unrefTimer->{when} > $when) {
                debug('unrefTimer is scheduled to fire too late, reschedule');
                $unrefTimer->start($msecs, 0);
                $unrefTimer->{when} = $when;
            }
            
            return;
        }
    }

    debug('unrefList append to end');
    $L->append($unrefList, $item);
}

sub start_timers { Rum::Wrap::Timers::run_timers() }
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
        $this->{_repeat}      = 0;
        return $this;
    }
    
    sub unref {
        my $this = shift;
        if (!$this->{_handle}) {
            my $now = Rum::Timers::now();
            $this->{_idleStart} = $now if !$this->{_idleStart};
            my $delay = $this->{_idleStart} + $this->{_idleTimeout} - $now;
            $delay = 0 if ($delay < 0);
            Rum::Timers::unenroll($this);
            $this->{_handle} = Rum::Wrap::Timers->new();
            $this->{_handle}->{ontimeout} = $this->{_onTimeout};
            $this->{_handle}->start($delay, 0);
            $this->{_handle}->{domain} = $this->{domain};
            $this->{_handle}->unref();
        } else {
            $this->{_handle}->unref();
        }
        return $this;
    }
    
    sub ref {
        my $this = shift;
        if ($this->{_handle}) {
            $this->{_handle}->ref();
        }
        return $this;
    }
    
    sub close {
        my $this = shift;
        $this->{_onTimeout} = undef;
        if ($this->{_handle}) {
            $this->{_handle}->{ontimeout} = undef;
            $this->{_handle}->close();
        } else {
            Rum::Timers::unenroll($this);
        }
    }
    
}



package Rum::Timers::Immediate; {
    
    sub new {
        return bless {
            _asyncFlags => 0
        },'Rum::Timers::Immediate';
    }

    #Immediate.prototype.domain = undefined;
    #Immediate.prototype._onImmediate = undefined;
    #Immediate.prototype._asyncQueue = undefined;
    #Immediate.prototype._asyncData = undefined;
    #Immediate.prototype._idleNext = undefined;
    #Immediate.prototype._idlePrev = undefined;
    #Immediate.prototype._asyncFlags = 0;
    
    
    
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
at the same time and gave a good results, in some cases - comparing - to nodejs it showed better memory usage and faster
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

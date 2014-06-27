package Rum;
use strict;
use warnings;

use Rum::Loop;

use utf8;
use Data::Dumper;
use Rum::Timers ();
use Rum::Module;
use Rum::Buffer;
use Rum::TryCatch ();
use Cwd();
use Carp;
use FindBin qw($Bin);

use Rum::IO;

our $VERSION = '0.001';

## Global Variables =====================================================
my $SELF;
my $PROCESS;
my $prog_start_time;
my $force_repl = 0;
my $is_print = 0;
my $is_eval = 0;
my $eval_string;
my $print_eval = 0;
my @new_args;
my @execArgs;

## handles ==============================================================
my $immediate_check_handle        = {};
my $immediate_idle_handle         = {};
my $idle_prepare_handle           = {};
my $idle_check_handle             = {};
my $dispatch_debug_messages_async = {};

my $loop = Rum::Loop::main_loop();

## Exports ==============================================================
use base qw/Exporter/;
our @EXPORT = qw (
    _default_loop
    process
    Buffer
    setTimeout
    setInterval
    setImmediate
    clearInterval
    clearTimeout
    Require
    exports
    module
    try
    catch
    finally
    __filename
    __dirname
);

sub import {
    my ($class, @options) = @_;
    strict->import;
    warnings->import;
    utf8->import;
    $class->export_to_level(1, $class, @options);
    return;
}

sub loop {
    &Rum::Loop::default_loop;
}

sub new {
    return $SELF if $SELF;
    $SELF = bless {}, shift;
    my $platform = $^O eq 'MSWin32' ? 'win32' : 'linux';
    $SELF->{platform} = $platform;
    use FindBin qw($RealScript);
    $SELF->{execPath} = $Bin . ($platform eq 'win32' ? '/rum.bat' : '/rum.sh');
    my @args = @ARGV;
    unshift @args, $SELF->{execPath};
    $SELF->{argv} = \@args;
    $SELF->{events} = {};
    $ENV{'Rum'} = $VERSION;
    return $SELF;
}

#========================================================================
#                            GLOBAL Functions
#========================================================================
sub Buffer        {   'Rum::Buffer'                   }
sub try (&;@)     {   &Rum::TryCatch::try            }
sub catch (&;@)   {   &Rum::TryCatch::catch          }
sub finally (&;@) {   &Rum::TryCatch::finally        }
sub setTimeout    {   &Rum::Timers::setTimeout       }
sub setInterval   {   &Rum::Timers::setInterval      }
sub setImmediate  {   &Rum::Timers::setImmediate     }
sub clearTimeout  {   &Rum::Timers::clearTimeout     }
sub clearInterval {   &Rum::Timers::clearInterval    }
sub Require       {   &Rum::Module::Require          }
sub module        {{}}
sub exports       {{}}
sub __dirname     {''}
sub __filename    {''}
sub process       {    $PROCESS   }

##overriding Rum::Timers::MakeCallback
##this exists for the reason when some one want to use timers
##module as a stand alone module
{
    no warnings 'redefine';
    *Rum::Timers::MakeCallback = \&MakeCallback;
}
sub MakeCallback {
    my ($obj,$name) = (shift,shift);
    MakeCallback2($obj,$name,$obj,@_);
    Rum::Process::_tickCallback();
}

sub MakeCallback2x {
    my $obj = shift;
    my $action = shift;
    $obj->{$action}->(@_);
    Rum::Process::_tickCallback();
}

my $in_tick = 0;
sub MakeCallback2 {
    
    my $handle = shift;
    my $string = shift;
    my @args = @_;
    my $callback = $handle->{$string};
    
    #if (env->using_domains())
    #  return MakeDomainCallback(env, recv, callback, argc, argv);
    my $process = process();
    
    #TryCatch try_catch;
    #try_catch.SetVerbose(true);
    
    #// TODO(trevnorris): This is sucky for performance. Fix it.
    #bool has_async_queue =
    #    recv->IsObject() && recv.As<Object>()->Has(env->async_queue_string());
    #if (has_async_queue) {
    #  env->async_listener_load_function()->Call(process, 1, &recv);
    #  if (try_catch.HasCaught())
    #    return Undefined(env->isolate());
    #}
    my $ret;
    
    try {
        $ret = $callback->(@args);
    } catch {
        die @_;
        #print Dumper $string;
        return;
    };
    
    #Local<Value> ret = callback->Call(recv, argc, argv);

    #if (has_async_queue) {
    #  env->async_listener_unload_function()->Call(process, 1, &recv);

    #if (try_catch.HasCaught())
    #  return Undefined(env->isolate());
    #}

    my $tick_info = $process->tick_info();

    if ( $tick_info->{in_tick} ) {
        return $ret;
    }
    
    if ($tick_info->{kLength} == 0) {
        $tick_info->{kIndex} = 0;
        return $ret;
    }
    
    $tick_info->{in_tick} = 1;
    Rum::Process::_tickCallback();
    $tick_info->{in_tick} = 0;
    
    #if (try_catch.HasCaught()) {
    #  tick_info->set_last_threw(true);
    #  return Undefined(env->isolate());
    #}
    
    return $ret;
}




sub ParseArgs {   
    @new_args = ($SELF->{execPath});
    @new_args = ($SELF->{execPath},'') and return if !@ARGV;
    
    if ($ARGV[0] !~ /^-/) {
        push @new_args, @ARGV;
        return;
    }
    
    my $i = 0;
    foreach my $arg (@ARGV) {
        if ($arg !~ /^-/) {
            last;
        }
        
        push @execArgs, $ARGV[$i];
        if ($arg =~ /^--debug/) {
            ##ParseDebugOpt($arg);
        }
        elsif ($arg eq '-v' || $arg eq '--version') {
            printf("%s\n", $VERSION);
            exit(0);
        }
        elsif ($arg eq '-h' || $arg eq '--help') {
            print "help\n";
            exit;
        }
        elsif ($arg eq '-i' || $arg eq '--interactive') {
            $force_repl = 1;
        }
        elsif ($arg eq '-e' || $arg eq '--eval' || $arg eq '--print' || $arg eq '-p') {
            $is_eval  = $arg =~ /-e/;
            $is_print = $arg =~ /-p/;
            $print_eval = $print_eval  || $is_print;
            if ($is_eval && !$ARGV[$i + 1]) {
                die "$arg requires an argument";
            } else {
                $eval_string = $ARGV[$i + 1];
            }
        } else {
            die "unrecognized argument flag $arg";
        }
        $i++;
    }
    
    push @new_args, (@ARGV[$i .. (scalar @ARGV)-1 ]);
}

sub Init {
    
    #Initialize prog_start_time to get relative uptime.
    $prog_start_time = time();
    
    #Make inherited handles noninheritable.
    #uv_disable_stdio_inheritance();
    
    #init async debug messages dispatching
    #FIXME(bnoordhuis) Should be per-isolate or per-context, not global.
    ## TO DO
    #$loop->async_init($dispatch_debug_messages_async,\&DispatchDebugMessagesAsyncCallback);
    #Rum::Loop::unref($dispatch_debug_messages_async);
    
    #Parse arguments which are specific to Node.
    ParseArgs();
    
    #if (debug_wait_connect) {
    #    const char expose_debug_as[] = "--expose_debug_as=v8debug";
    #    V8::SetFlagsFromString(expose_debug_as, sizeof(expose_debug_as) - 1);
    #}
    
    #const char typed_arrays_flag[] = "--harmony_typed_arrays";
    #V8::SetFlagsFromString(typed_arrays_flag, sizeof(typed_arrays_flag) - 1);
    #V8::SetArrayBufferAllocator(&ArrayBufferAllocator::the_singleton);
    
    ###TO DO
    #using BSD::Resource is an option
    
    #ifdef __POSIX__
    # Raise the open file descriptor limit.
    #// Ignore SIGPIPE
    #RegisterSignalHandler(SIGPIPE, SIG_IGN);
    #RegisterSignalHandler(SIGINT, SignalExit);
    #RegisterSignalHandler(SIGTERM, SignalExit);
    #endif  // __POSIX__
    
    #// If the --debug flag was specified then initialize the debug thread.
    #if (use_debug_agent) {
    #    EnableDebug(debug_wait_connect);
    #} else {
    #    RegisterDebugSignalHandler();
    #}
}

sub SetupProcessObject {
    my $process = $PROCESS = bless {
        env => \%ENV,
        cwd => Cwd::cwd,
        emit => \&Rum::Events::emit,
        platform => $SELF->{platform}
    },'Rum::Process';
    
    # -e, --eval
    if ($eval_string) {
        $process->{"_eval"} = $eval_string;
    }
    
    # -p, --print
    if ($print_eval) {
        $process->{_print_eval} = 1;
    }
    
    # -i, --interactive
    if ($force_repl) {
        $process->{_forceRepl} = 1;
    }
}

sub Load {
    my $f = require 'rum.pl';
    $f->();
}

sub CreateEnvironment {
    $loop->check_init($immediate_check_handle);
    $loop->unref($immediate_check_handle);
    $loop->idle_init($immediate_idle_handle);
    $loop->prepare_init($idle_prepare_handle);
    $loop->check_init($idle_check_handle);
    $loop->unref($idle_prepare_handle);
    $loop->unref($idle_check_handle);
    SetupProcessObject();
    Load();
}

sub run {
    my $self = shift;
    my $file = shift;
    
    Init();
    
    CreateEnvironment();
    my $code;
    my $more = 0;
    do {
        Rum::Process::_tickCallback();
        $more = $loop->run(RUN_ONCE);
        if (!$more) {
            EmitBeforeExit();
            #Emit `beforeExit` if the loop became alive either after emitting
            #event, or after running some callbacks.
            $more = $loop->loop_alive();
            if ($loop->run(RUN_NOWAIT) != 0){
                $more = 1;
            }
        }
    } while ( $more );
    $code = EmitExit();
    RunAtExit();
    
    Rum::Process::_tickCallback();
    #$loop->run();
    #EmitExit();
}

sub NeedImmediateCallbackGetter {
    return Rum::Loop::is_active($immediate_check_handle);
}

sub NeedImmediateCallbackSetter {
    my $self = shift;
    my $value = shift;
    
    my $active = Rum::Loop::is_active($immediate_check_handle);
    
    if ( $active == $value ) {
        return;
    }
    
    if ( $active ) {
        $loop->check_stop($immediate_check_handle);
        $loop->idle_stop($immediate_idle_handle);
    } else {
        $loop->check_start($immediate_check_handle, \&CheckImmediate);
        #Idle handle is needed only to stop the event loop from blocking in poll.
        $loop->idle_start($immediate_idle_handle, \&IdleImmediateDummy);
    }
}

sub  IdleImmediateDummy {}

sub EmitBeforeExit {
    my $code = process()->{exitCode} || 0;
    my @args = ('beforeExit',$code);
    MakeCallback(process(), "emit", @args);
}

sub EmitExit {
    my $self = shift;
    process->{_exiting} = 1;
    
    my $code = process()->{exitCode} || 0;
    my @args = ('exit',$code);
    
    MakeCallback(process(), "emit", @args);
    return $code;
}

sub RunAtExit {
    
}

sub CheckImmediate {
    MakeCallback2(process(), '_immediateCallback');
}


#========================================================================
# Process Package
#========================================================================
package Rum::Process; {
    use strict;
    use warnings;
    use base 'Rum::Events';
    
    my @nextTickQueue = ();
    
    use Data::Dumper;
    sub execPath { $SELF->{execPath} }
    sub execArgs { \@execArgs }
    sub argv { \@new_args }
    sub env { shift->{env} }
    sub platform { shift->{platform} || $SELF->{platform} }
    sub cwd { shift->{cwd} || $SELF->{cwd} }
    sub umask { shift; CORE::umask(shift) }
    sub domain { undef }
    
    #my $tickInfo = {
    #    kInTick => 0,
    #    kIndex => 0,
    #    kLastThrew => 0,
    #    kLength => 0
    #};
    #
    #sub nextTick {
    #    my ($self,$callback) = @_;
    #    #on the way out, don't bother. it won't get fired anyway.
    #    return if $self->{_exiting};
    #    
    #    push @nextTickQueue, {
    #        callback => $callback,
    #        domain => $self->domain || undef
    #    };
    #    
    #    $tickInfo->{kLength}++;
    #}
    #
    #sub tickDone {
    #    if ($tickInfo->{kLength} != 0) {
    #        if ($tickInfo->{kLength} <= $tickInfo->{kIndex}) {
    #            @nextTickQueue = ();
    #            $tickInfo->{kLength} = 0;
    #        } else {
    #            splice @nextTickQueue, 0, $tickInfo->{kIndex};
    #            $tickInfo->{kLength} = @nextTickQueue;
    #        }
    #    }
    #    $tickInfo->{kInTick} = 0;
    #    $tickInfo->{kIndex} = 0;
    #}
    #
    #sub _tickCallback {
    #    my $callback;
    #    my $threw;
    #    
    #    $tickInfo->{kInTick} = 1;
    #    while ( $tickInfo->{kIndex} < $tickInfo->{kLength}) {
    #        my $callback = $nextTickQueue[$tickInfo->{kIndex}++]->{callback};
    #        $threw = 1;
    #        Rum::try {
    #            $callback->();
    #            $threw = 0;
    #        } Rum::finally {
    #            tickDone() if $threw;
    #        } Rum::catch {
    #            Rum::process->emit('uncaughtException',$_);
    #        };
    #    }
    #    
    #    tickDone();
    #}
    
    sub _setupNextTick {
        my $self = shift;
        my $tick_info_obj = shift;
        my $callback = shift;
        $self->{tick_callback_function} = $callback;
    }
    
    sub _needImmediateCallback {
        &Rum::NeedImmediateCallbackGetter
    }
    
    sub _needImmediateCallbackSetter {
        &Rum::NeedImmediateCallbackSetter
    }
    
    sub disconnect {
        my $this = shift;
        $this->{disconnect}->($this);
    }
    
    sub _disconnect {
        my $this = shift;
        $this->{_disconnect}->($this);
    }
    
    sub send {
        my $this = shift;
        $this->{send}->($this, @_);
    }
    
    sub _send {
        my $this = shift;
        $this->{_send}->($this, @_);
    }
    
    #sub stdin    {{}}
}

1;

__END__

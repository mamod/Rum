package Rum::Wrap::Process;
use strict;
use warnings;
use Rum::Wrap::Handle;
use Data::Dumper;
use Rum::Loop;
use Rum::Loop::Flags qw[:Process :Stdio :Platform];
use Rum::Loop::Utils 'assert';
my $util = 'Rum::Utils';
my $loop = Rum::Loop::default_loop();

sub new {
    my $this = bless {}, __PACKAGE__;
    my $process_ = {};
    Rum::Wrap::Handle::HandleWrap($this, $process_);
    return $this;
}

sub spawn {
    my $this = shift;
    my $js_options = shift;
    my $wrap = $this;
    my $options = {};
    
    $options->{exit_cb} = \&OnExit;
    $options->{flags}   = 0;
    
    #options.uid
    my $uid = $js_options->{uid};
    
    if ($util->isNumber($uid)) {
        $options->{flags} |= $PROCESS_SETUID;
        $options->{uid} = $uid;
    } elsif ($uid){
        die "options.uid should be a number";
    }
    
    #options.gid
    my $gid = $js_options->{gid};
    
    if ($util->isNumber($gid)) {
        $options->{flags} |= $PROCESS_SETGID;
        $options->{gid} = $gid;
    } elsif ($gid){
        die "options.gid should be a number";
    }
    
    #options.file
    my $file = $js_options->{file};
    
    if ($file) {
        $options->{file} = $file;
    } else {
        die("Bad argument");
    }
    
    #options.args
    my $argv = $js_options->{args};
    
    if ($util->isArray($argv)) {
        $options->{args} = $argv;
    }
    
    #options.cwd
    my $cwd = $js_options->{cwd};
    if ($cwd) {
        $options->{cwd} = $cwd;
    }
    
    #options.env
    my $env = $js_options->{envPairs};
    $options->{env} = $env;
    
    #options.stdio
    ParseStdioOptions($js_options, $options);

    #options.detached
    my $detached = $js_options->{detached};
    if ($detached) {
        $options->{flags} |= $PROCESS_DETACHED;
    }
    
    $! = 0;
    my $ret = $loop->spawn($wrap->{handle__}, $options);
    if ($ret) {
        assert(getHandleData($wrap->{handle__}) == $wrap);
        $wrap->{pid}  = $wrap->{handle__}->{pid};
    }
    
    undef $options;
    return $!;
}

sub ParseStdioOptionsx {
    my $js_options = shift;
    my $options = shift;
    my $stdios = $js_options->{stdio};
    my $len = scalar @{$stdios};
    $options->{stdio} = Rum::Loop::Process::stdio_container($len);
    $options->{stdio_count} = $len;
}

sub ParseStdioOptions {
    my ($js_options, $options) = @_;
    my $stdios = $js_options->{stdio};
    my $len = scalar @{$stdios};
    
    $options->{stdio} = Rum::Loop::Process::stdio_container($len);
    $options->{stdio_count} = $len;
    
    for (my $i = 0; $i < $len; $i++){
        my $stdio = $stdios->[$i];
        my $type = $stdio->{type};
        if ($type eq 'ignore') {
            $options->{stdio}->[$i]->{flags} = $IGNORE;
        } elsif ($type eq 'pipe'){
            $options->{stdio}->[$i]->{flags} = $CREATE_PIPE | $READABLE_PIPE | $WRITABLE_PIPE;
            my $handle = $stdio->{handle};
            $options->{stdio}->[$i]->{data}->{stream} = $handle->{handle__};
        } elsif ($type eq 'wrap'){
            my $handle = $stdio->{handle};
            my $stream = HandleToStream($handle);
            assert($stream);
            $options->{stdio}->[$i]->{flags} = $INHERIT_STREAM;
            $options->{stdio}->[$i]->{data}->{stream} = $stream;
        } else {
            my $fd = $stdio->{fd};
            $options->{stdio}->[$i]->{flags} = $INHERIT_FD;
            $options->{stdio}->[$i]->{data}->{fd} = $fd;
        }
    }
}

sub OnExit {
    my ($handle, $exit_status, $term_signal) = @_;
    my $wrap = getHandleData($handle);
    assert($wrap);
    assert($wrap->{handle__} == $handle);
    Rum::MakeCallback2($wrap,'onexit',$exit_status,$term_signal);
}

sub kill {
    my $wrap = shift;
    my $signal = shift;
    if (!$loop->process_kill($wrap->{handle__}, $signal)){
        return $!;
    }
    
    return 0;
}

1;

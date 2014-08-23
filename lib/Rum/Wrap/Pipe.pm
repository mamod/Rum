package Rum::Wrap::Pipe;
use strict;
use warnings;
use Rum::Wrap::Handle;
use Rum::Wrap::Stream qw(
    readStart
    readStop
    shutdown
    writeBuffer
    writeAsciiString
    writeUtf8String
    writeUcs2String
    stream
    UpdateWriteQueueSize
);

use Data::Dumper;
use Rum::Loop;
use FileHandle;
use Socket;
use Rum::Loop::Flags ':Platform';
my $util = 'Rum::Utils';

use IO::Handle;
my $io = IO::Handle->new();

my $loop = Rum::Loop::default_loop();

sub new {
    my $class = shift;
    my $ipc = shift;
    my $this = bless {}, $class;
    my $handle_ = {};
    Rum::Wrap::Stream::StreamWrap($this, $handle_);
    $loop->pipe_init($handle_, $ipc);
    $this->UpdateWriteQueueSize();
    $this->{writev} = 0;
    return $this;
}

sub listen {
    my $wrap = shift;
    my $backlog = shift;
    $loop->listen($wrap->{handle__},
                    $backlog,
                    \&OnConnection) or return $!;
    return 0;
}

sub open {
    my $wrap = shift;
    my $fd = shift;
    my $fh;
    
    if ($isWin) {
        my $shared_handles = delete $ENV{NODE_WIN_HANDLES};
        my @pairs = split /#/, $shared_handles;
        foreach my $pair (@pairs) {
            my ($fd2,$fhandle) = split /,/, $pair;
            if ($fd2 == $fd) {
                $fh = new FileHandle;
                Rum::Loop::Core::OsFHandleOpen($fh, $fhandle, 'rw') or die $^E;
            }
        }
    } else {
        open($fh, ">&=$fd") or die "couldn't fdopen $fd: $!";
    }
    
    $loop->pipe_open($wrap->{handle__}, $fh) or die $!;
}

1;

package Rum::Wrap::TTY;
use strict;
use warnings;
use Rum::Utils;
my $util = 'Rum::Utils';
use Rum::Wrap::Stream qw(
    readStart
    readStop
    shutdown
    writeBuffer
    writeAsciiString
    writeUtf8String
    writeUcs2String
    writev
    stream
    UpdateWriteQueueSize
);

use Rum::Wrap::Handle qw(close ref unref);
use Data::Dumper;
my $loop = Rum::Loop::default_loop();

sub new {
    my $class = shift;
    my $fh = shift;
    my $readable = shift;
    
    my $handle_ = {};
    my $this = bless {}, $class;
    Rum::Wrap::Stream::StreamWrap($this,$handle_,1);
    
    $loop->tty_init($handle_, $fh);
    $this->UpdateWriteQueueSize();
    return $this;
}


sub guessHandleType {
    
    my $fh = shift;
    
    return 'UNKNOWN' if !$fh; 
    
    if ($util->isNumber($fh)) {
        my $fd = $fh;
        $fh = undef;
        open($fh, ">&=", $fd) or die $!;
    }
    
    #my $io = IO::Handle->new();
    #my $fh = $io->fdopen($args->[0], 'w') or Pode::throe($!);
    
    my $type = '';
    if (-t $fh){
        $type = 'TTY';
    } elsif (-p $fh){
        $type = 'PIPE';
    } elsif (-S $fh) {
        $type = 'TCP';
    }elsif (-f $fh){
        $type = 'FILE';
    } else {
        $type = 'UNKNOWN';
    }
    
    return $type;
}


1;

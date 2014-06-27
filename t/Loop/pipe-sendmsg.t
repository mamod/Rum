use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Utils 'assert';
use Rum::Loop::Flags qw[:Stdio :Platform];
use POSIX 'errno_h';
use Data::Dumper;
use Socket;

*set_nonblocking = \&Rum::Loop::Core::nonblock;

use Rum::Loop::SendRecv;

use Test::More;
*ASSERT = *ok;

#NOTE: size should be divisible by 2
my $incoming = [{},{},{},{}];
my $incoming_count = 0;
my $close_called   = 0;

my $loop = Rum::Loop::default_loop();

sub close_cb {
    $close_called++;
}

sub read_cb {
    my ($handle,$nread, $buf) = @_;
    my $p = {};
    my $inc = {};
    my $pending = {};
    my $i = 0;
    
    $p = $handle;
    ASSERT($nread >= 0);
    while ($loop->pipe_pending_count($p) != 0) {
        $pending = $loop->pipe_pending_type($p);
        
        ASSERT($pending eq 'NAMED_PIPE', $pending) if !$isWin;
        ASSERT($pending eq 'TCP', $pending) if $isWin;
        
        ASSERT($incoming_count < @{$incoming} );
        $inc = $incoming->[$incoming_count++];
        #$p->{loop}->pipe_init($inc, 0);
        $loop->pipe_init($inc, 0);
        $loop->accept($handle, $inc) or die $!;
    }
    
    if ($incoming_count != scalar @{$incoming}){
        return;
    }
    
    $loop->read_stop($p);
    $loop->close($p, \&close_cb);
    foreach my $c (@{$incoming}) {
        $loop->close($c, \&close_cb);
    }
}

#TEST_IMPL(pipe_sendmsg) 
{
    my $p = {};
    my $fds = [];
    my $send_fds = [[],[],[],[]];
    
    socketpair(my $fd0, my $fd1, AF_UNIX, SOCK_STREAM, 0) or die $!;
    $fds->[0] = $fd0;
    $fds->[1] = $fd1;
    
    foreach my $pair ( @{$send_fds} ) {
        socketpair($pair->[0], $pair->[1], AF_UNIX, SOCK_STREAM, 0) or die $!;
    }
    
    $loop->pipe_init($p, 1);
    $loop->pipe_open($p, $fds->[1]) or die $!;
    
    my $buf = $loop->buf_init("X", 1);
    
    #my $msg = Rum::Loop::SendRecv->new(buf  => "X");
    
    #pack("i*", map{ fileno $_->[0] } @{$send_fds});
    my @ctldata;
    map {
        push @ctldata, fileno $_->[0];
    } @{$send_fds};
    
    set_nonblocking($fds->[1],1);
    
    $loop->read_start($p, \&read_cb) or die $!;
    
    my $r;
    do {
        $r = sendmsg($fds->[0], "X", \@ctldata, 0);
    } while (!defined $r && $! == EINTR);
    
    $loop->run(RUN_DEFAULT);
    ASSERT(@{$incoming} == $incoming_count);
    ASSERT(@{$incoming} + 1 == $close_called);
    close($fds->[0]);
}

done_testing();

1;

use lib '../../lib';
use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Utils 'assert';
use Rum::Loop::Flags ':Platform';
use POSIX 'errno_h';
use Data::Dumper;
use Test::More;
my $loop = Rum::Loop->new();

my $TEST_PORT = 9090;
my $EOF = -4095;

my $addr;
my $tcp_server = {};
my $tcp_outgoing = [{ __id => 0 },{ __id => 1 }];
my $tcp_incoming = [{ __id => 0 },{ __id => 1 }];
my $connect_reqs = [{ __id => 0 },{ __id => 1 }];
my $tcp_check = {};
my $tcp_check_req = {};
my $write_reqs = [{ __id => 0 },{ __id => 1 }];
my $got_connections = 0;
my $close_cb_called = 0;
my $write_cb_called = 0;
my $read_cb_called = 0;

sub close_cb {
    $close_cb_called++;
}

sub write_cb {
    my ($req, $status) = @_;
    ok($status == 0);
    $write_cb_called++;
}

sub connect_cb {
    my ($req, $status) = @_;
    my $i = 0;
    my $buf = {};
    my $outgoing = {};

    if ($req == $tcp_check_req) {
        
        ## Close check and incoming[0], time to finish test */
        ###$loop->close($tcp_incoming->[0], \&close_cb);


        if ($isWin){
            diag('FIXME: windows gives no errors');
        } else {
            ok($status != 0, $!);
        }
        for (@{$tcp_incoming}) {
            $loop->close($_, \&close_cb) if $_->{__first};
        }
       
        $loop->close($tcp_check, \&close_cb);
        return;
    }

    ok($status == 0);
    
    $i = $req->{__id};
    $buf = $loop->buf_init("x", 1);
    $outgoing = $tcp_outgoing->[$i];
    $loop->write($write_reqs->[$i], $outgoing, $buf, 1, \&write_cb);
}

# sub read_cb {
#    my ($stream, $nread, $buf) = @_;
#    my $i = 0;
#    #Only first stream should receive read events */
#    print $tcp_incoming->[0] . "\n";
#    #print $stream . "\n";

#    ok($stream == $tcp_incoming->[0]);
#    $loop->read_stop($stream);
#    ok(1 == $nread, $nread);
   
#    $read_cb_called++;

#    #Close all active incomings, except current one */
#    for ($i = 1; $i < $got_connections; $i++) {
#        $loop->close($tcp_incoming->[$i], \&close_cb);
#    }
 
#    #Create new fd that should be one of the closed incomings */
#    $loop->tcp_init($tcp_check);
#    ok(1 == $loop->tcp_connect($tcp_check,
#                            $tcp_check_req,
#                            $addr,
#                            \&connect_cb), $!);
   
#    $loop->read_start($tcp_check, \&read_cb);

#    #/* Close server, so no one will connect to it */
#    $loop->close($tcp_server, \&close_cb);
# }

sub read_cb {
    my ($stream, $nread, $buf) = @_;
    my $i = 0;
    #Only first stream should receive read events
    $stream->{__first} = 1;
    
    #ok($stream == $tcp_incoming->[0]);
    $loop->read_stop($stream);
    ok(1 == $nread);
    
    $read_cb_called++;

    #Close all active incomings, except current one
    for (@{$tcp_incoming}) {
        next if $_ == $stream;
        $loop->close($_, \&close_cb);
    }
  
    #Create new fd that should be one of the closed incomings
    $loop->tcp_init($tcp_check);
    ok($loop->tcp_connect($tcp_check,
                            $tcp_check_req,
                            $addr,
                            \&connect_cb));
    
    $loop->read_start($tcp_check, \&read_cb);

    # Close server, so no one will connect to it
    $loop->close($tcp_server, \&close_cb);
}

sub connection_cb {
    my ($server, $status) = @_;
    my $i = 0;
    
    ok($server == $tcp_server);
    
    #/* Ignore tcp_check connection */
    if ($got_connections == ARRAY_SIZE($tcp_incoming)){
        return;
    }

    #/* Accept everyone */
    my $incoming = $tcp_incoming->[$got_connections++];
    $loop->tcp_init($incoming);
    $loop->accept($server, $incoming) or die $!;
    
    if ($got_connections != ARRAY_SIZE($tcp_incoming)){
        return;
    }

    #/* Once all clients are accepted - start reading */
    for ($i = 0; $i < ARRAY_SIZE($tcp_incoming); $i++) {
        $incoming = $tcp_incoming->[$i];
        $loop->read_start($incoming, \&read_cb);
    }
}

sub ARRAY_SIZE {
    my $arr = shift;
    return scalar @{$arr};
}

{
    my $i = 0;

    #* A little explanation of what goes on below:
    #*
    #* We'll create server and connect to it using two clients, each writing one
    #* byte once connected.
    #*
    #* When all clients will be accepted by server - we'll start reading from them
    #* and, on first client's first byte, will close second client and server.
    #* After that, we'll immediately initiate new connection to server using
    #* tcp_check handle (thus, reusing fd from second client).
    #*
    #* In this situation uv__io_poll()'s event list should still contain read
    #* event for second client, and, if not cleaned up properly, `tcp_check` will
    #* receive stale event of second incoming and invoke `connect_cb` with zero
    #* status.

    $addr = $loop->ip4_addr("127.0.0.1", $TEST_PORT) or fail $!;
    
    $loop->tcp_init($tcp_server);
    $loop->tcp_bind($tcp_server, $addr, 0) or fail $!;
    $loop->listen($tcp_server,
                        ARRAY_SIZE($tcp_outgoing),
                        \&connection_cb) or fail $!;

    for ($i = 0; $i < ARRAY_SIZE($tcp_outgoing); $i++) {
        my $client = $tcp_outgoing->[$i];
        
        $loop->tcp_init($client);
        $loop->tcp_connect($client,
                            $connect_reqs->[$i],
                            $addr,
                            \&connect_cb) or fail $!;
    }

    $loop->run(RUN_DEFAULT);

    ok(ARRAY_SIZE($tcp_outgoing) == $got_connections);
    ok((ARRAY_SIZE($tcp_outgoing) + 2) == $close_cb_called);
    ok(ARRAY_SIZE($tcp_outgoing) == $write_cb_called);
    ok(1 == $read_cb_called);

}

done_testing();

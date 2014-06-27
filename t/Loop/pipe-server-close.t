use lib './lib';
use Rum::Loop;
#use Rum::Loop::Utils 'assert';
use POSIX qw(:errno_h);
use strict;
use warnings;
use Data::Dumper;

use Test::More;
*assert = *ok;

my $loop = Rum::Loop::default_loop();

my $pipe_client = {};
my $pipe_server = {};
my $connect_req = {};

my $pipe_close_cb_called = 0;
my $pipe_client_connect_cb_called = 0;

sub pipe_close_cb {
    my ($handle) = @_;
    assert($handle == $pipe_client || $handle == $pipe_server);
    $pipe_close_cb_called++;
}

sub pipe_client_connect_cb {
    my ($req, $status) = @_;
    assert($req == $connect_req);
    assert(!$status);
    
    $pipe_client_connect_cb_called++;
    
    $loop->close($pipe_client, \&pipe_close_cb);
    $loop->close($pipe_server, \&pipe_close_cb);
}


sub pipe_server_connection_cb {
    my ($handle, $status) = @_;
    #This function *may* be called, depending on whether accept or the
    #connection callback is called first.
    assert(!$status);
}

{
    my  $TEST_PIPENAME = "/tmp/sock1";
    my  $TEST_PIPENAME2 = "/tmp/sock1";
    
    unlink $TEST_PIPENAME;
    $loop->pipe_init($pipe_server, 0);
    
    $loop->pipe_bind($pipe_server, $TEST_PIPENAME) or die $!;
    
    $loop->listen($pipe_server, 0, \&pipe_server_connection_cb) or die $!;
    
    $loop->pipe_init($pipe_client, 0);
    
    $loop->pipe_connect($connect_req, $pipe_client, $TEST_PIPENAME2, \&pipe_client_connect_cb);
    
    $loop->run(RUN_DEFAULT);
    assert($pipe_client_connect_cb_called == 1);
    assert($pipe_close_cb_called == 2);
}

done_testing();

1;

use lib './lib';
use Rum::Loop;
use Test::More;
use POSIX qw(:errno_h);
use strict;
use warnings;
use Data::Dumper;
use Rum::Loop::Flags ':Platform';

my $loop = Rum::Loop::default_loop();

*assert = *ok;

#ifdef _WIN32
#my $BAD_PIPENAME  = "bad-pipe";
#else
my $BAD_PIPENAME = "/path/to/unix/socket/that/really/should/not/be/there";
#endif

my $TEST_PIPENAME = "/tmp/uv-test-sock";
my $TEST_PIPENAME_2 = "/tmp/uv-test-sock2";

unlink $TEST_PIPENAME;
unlink $TEST_PIPENAME_2;

my $close_cb_called = 0;


sub close_cb {
    my $handle = shift;
    #ASSERT(handle != NULL);
    $close_cb_called++;
}

{
    my $server1 = {};
    my $server2 = {};
    
    $loop->pipe_init($server1, 0);
    $loop->pipe_bind($server1, $TEST_PIPENAME);
    
    $loop->pipe_init($server2, 0);
    
    $loop->pipe_bind($server2, $TEST_PIPENAME);
    assert($! == EADDRINUSE);
    
    $loop->listen($server1, 127, undef) or die $!;
    
    $loop->listen($server2, 127, undef);
    assert($! == EINVAL);
    
    $loop->close($server1, \&close_cb);
    $loop->close($server2, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    assert($close_cb_called == 2);
}

{
    my $server = {};
    $close_cb_called = 0;
    $loop->pipe_init($server, 0);
    
    my $tt = $loop->pipe_bind($server, $BAD_PIPENAME);
    diag("FIXME: windows Error 65");
    assert($! == EACCES) if !$isWin;
    
    $loop->close($server, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    assert($close_cb_called == 1);
}

{
    my $server = {};
    $close_cb_called = 0;
    $loop->pipe_init($server, 0);
    
    $loop->pipe_bind($server, $TEST_PIPENAME) or die $!;
    
    $loop->pipe_bind($server, $TEST_PIPENAME_2);
    assert($! == EINVAL, $!);
    
    $loop->close($server, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    assert($close_cb_called == 1);

}

{
    my $server = {};
    $close_cb_called = 0;
    
    $loop->pipe_init($server, 0);
    
    $loop->listen($server, 127, undef);
    assert($! == EINVAL);
    
    $loop->close($server, \&close_cb);
    
    $loop->run(RUN_DEFAULT);
    
    assert($close_cb_called == 1);
}

done_testing();

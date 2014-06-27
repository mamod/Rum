use FindBin;
use lib "$FindBin::Bin/../../../lib";

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags ':Stdio';
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;

my $TEST_PORT = 9090;
my $EOF = -4095;

my $on_pipe_read_called = 0;
my $after_write_called = 0;
my $close_cb_called = 0;
my $stdin_pipe = {};
my $stdout_pipe = {};

my  $loop = Rum::Loop::default_loop();

sub close_cb {
    $close_cb_called++;
}

sub on_pipe_read {
    my ($tcp, $nread, $buf) = @_;
    assert($nread > 0);
    #assert(memcmp("hello world\n", buf->base, nread) == 0);
    $on_pipe_read_called++;
    undef $buf->{base};
    $loop->close($stdin_pipe, \&close_cb);
    $loop->close($stdout_pipe, \&close_cb);
}

sub after_pipe_write {
    my ($req, $status) = @_;
    assert($status == 0);
    $after_write_called++;
}

{
    #Write several buffers to test that the write order is preserved. */
    my @buffers = (
        "he",
        "ll",
        "o ",
        "wo",
        "rl",
        "d",
        "\n"
    );
    
    #  uv_write_t write_req[ARRAY_SIZE(buffers)];
    my $buf = [];
    
    my $write_req = [];
    
    my $x = 0;
    foreach my $b (@buffers){
        $write_req->[$x] = {};
        $buf->[$x] = $loop->buf_init($b);
        $x++;
    }
    
    #assert(UV_NAMED_PIPE == uv_guess_handle(0));
    #assert(UV_NAMED_PIPE == uv_guess_handle(1));
    
    #assert(-s *STDIN);
    #assert(-s *STDOUT);
    
    $loop->pipe_init($stdin_pipe, 0) or die $!;
    $loop->pipe_init($stdout_pipe, 0) or die $!;
    
    
    $loop->pipe_open($stdout_pipe, \*STDOUT) or die $!;
    $loop->pipe_open($stdin_pipe, \*STDIN) or die $!;
    
    #Unref both stdio handles to make sure that all writes complete. */
    $loop->unref($stdin_pipe);
    $loop->unref($stdout_pipe);
    
    for (my $i = 0; $i < scalar @buffers; $i++) {
        $loop->write($write_req->[$i], $stdout_pipe, $buf->[$i], 1,
        \&after_pipe_write) or die $!;
    }
    
    
    $loop->run(RUN_DEFAULT);
    
    assert($after_write_called == 7);
    assert($on_pipe_read_called == 0);
    assert($close_cb_called == 0);
    
    $loop->ref($stdout_pipe);
    $loop->ref($stdin_pipe);
    
    $loop->read_start($stdin_pipe, \&on_pipe_read);
    $loop->run(RUN_DEFAULT);
    
    assert($after_write_called == 7, $after_write_called);
    assert($on_pipe_read_called == 1);
    assert($close_cb_called == 2);
}

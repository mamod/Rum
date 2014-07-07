use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags ':Stdio';
#use Rum::Loop::Utils 'assert';
use Test::More;

use POSIX 'errno_h';
use Data::Dumper;
use FindBin qw($Bin);
my $EOF = -4095;

my $exepath = '';
my @args;
my $options = {};
my $close_cb_called = 0;
my $exit_cb_called = 0;
my $on_read_cb_called = 0;
my $after_write_cb_called = 0;

my $OUTPUT_SIZE = 1024;
my $output;
my $output_used = 0;
my $in;
my $out;
my $loop = Rum::Loop::default_loop();

*assert = *ok;

sub close_cb {
    $close_cb_called++;
}

sub exit_cb {
    my ($process, $exit_status, $term_signal) = @_;
    print("exit_cb\n");
    $exit_cb_called++;
    assert($exit_status == 0);
    assert($term_signal == 0);
    $loop->close($process, \&close_cb);
    $loop->close($in, \&close_cb);
    $loop->close($out, \&close_cb);
}

sub init_process_options {
    my $exit_cb = pop @_;
    #$args[0] = './spawn/stdio-over-pipe.pl';
    #$args[1] = $test;
    
    $options->{file} = 'perl';
    $options->{args} = \@_;
    $options->{exit_cb} = $exit_cb;
    $options->{flags} = 0;
}

sub after_write {
    my ($req, $status) = @_;
    if ($status) {
        printf("uv_write error: %s\n", $status);
        assert(0);
    }
    
    #Free the read/write buffer and the request
    undef $req;
    $after_write_cb_called++;
}

sub on_read {
    my ($tcp, $nread, $rdbuf) = @_;
    my $req = {};
    my $wrbuf = {};
    print Dumper $nread;
    assert($nread >= 0 || $nread == $EOF);
    
    if ($nread > 0) {
        $output_used += $nread;
        if ($output_used == 12) {
            $output = "hello world\n";
            #assert("hello world\n" eq $output);
            my $wrbuf = $loop->buf_init($output, $output_used);
            $loop->write($req, $in, $wrbuf, 1, \&after_write) or die $!;
        }
    }
    
    $on_read_cb_called++;
}


{
    
    my $process = {};
    my $stdio = [];
    
    init_process_options("$Bin/spawn/stdio-over-pipe.pl","stdio_over_pipes_helper", \&exit_cb);
    
    $loop->pipe_init($out, 0);
    $loop->pipe_init($in, 0);
    
    $options->{stdio} = $stdio;
    $options->{stdio}->[0]->{flags} = $CREATE_PIPE | $READABLE_PIPE;
    $options->{stdio}->[0]->{data}->{stream} = $in;
    $options->{stdio}->[1]->{flags} = $CREATE_PIPE | $WRITABLE_PIPE;
    $options->{stdio}->[1]->{data}->{stream} = $out;
    
    $options->{stdio_count} = 2;
    
    $loop->spawn($process, $options) or die $!;
    
    $loop->read_start($out, \&on_read) or die $!;
    
    $loop->run(RUN_DEFAULT);
    
    assert($on_read_cb_called > 1);
    assert($after_write_cb_called == 1);
    assert($exit_cb_called == 1);
    assert($close_cb_called == 3);
    assert ($output eq "hello world\n");
    assert($output_used == 12);
    done_testing();
}

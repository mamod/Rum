use lib './lib';

use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags ':Stdio';
#use Rum::Loop::Utils 'assert';
use Test::More;
use FindBin qw($Bin);
use POSIX 'errno_h';
use Data::Dumper;

my $TEST_PORT = 9090;
my $EOF = -4095;


my $exepath = '';
my @args;
my $options = {};
my $close_cb_called = 0;
my $exit_cb_called = 0;
my $on_read_cb_called = 0;
my $after_write_cb_called = 0;
my $in;
my $out;
my $loop = Rum::Loop::default_loop();
my $OUTPUT_SIZE = 1024;
my $output;
my $last_output = '';
my $output_used = 0;

my $should_get = 10000 * length "Hi";
my $should_get_total = $should_get + length "bye";

*assert = *ok;

sub close_cb {
    $close_cb_called++;
}

sub exit_cb {
    my ($process, $exit_status, $term_signal) = @_;
    print("exit_cb\n");
    $exit_cb_called++;
    assert($exit_status == 0, "exit status " . $exit_status);
    assert($term_signal == 0, "signal status " . $term_signal);
    $loop->close($process, \&close_cb);
    $loop->close($in, \&close_cb);
    $loop->close($out, \&close_cb);
}

sub init_process_options {
    my $exit_cb = pop @_;
    
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
    
    assert($nread >= 0 || $nread == $EOF);
    
    if ($nread > 0) {
        #print STDERR Dumper $rdbuf;
        $output_used += $nread;
        
        if ($output_used >= $should_get) {
            $last_output .= $rdbuf->{base};
        }
        
    }

    $on_read_cb_called++;
}


{
    
    my $process = {};
    my $stdio = [];
    
    init_process_options("$Bin/spawn/write-alot.pl", "stdio_over_pipes_helper", \&exit_cb);
    
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
    
    assert($exit_cb_called == 1);
    assert($close_cb_called == 3);
    
    $last_output = substr $last_output, length ($last_output) - 3;
    
    assert ($last_output eq "bye", "got $last_output");
    assert($output_used == $should_get_total, $should_get_total . " == $output_used");
    done_testing();
    
}

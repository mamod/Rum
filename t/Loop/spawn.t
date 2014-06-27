use lib './lib';
use Rum::Loop;
#use Rum::Loop::Utils 'assert';

use Test::More;
use FindBin qw($Bin);

use Rum::Loop::Flags qw(:Platform $EOF);
use POSIX qw(:errno_h);
use strict;
use warnings;
use Data::Dumper;

my $loop = Rum::Loop::default_loop();

my $timer33 = {};

my $close_cb_called = 0;
my $exit_cb_called = 0;
my $process = {};
my $timer = {};
my $options = {};
my $exepath = '';

my @args;
my $no_term_signal = 0;
my $timer_counter = 0;

#define OUTPUT_SIZE 1024
my $output = [];
my $output_used = 0;

*assert = *ok;

sub close_cb {
    printf("close_cb\n");
    $close_cb_called++;
    $loop->timer_stop($timer33);
}

sub exit_cb {
    my ($process,
                    $exit_status,
                    $term_signal) = @_;
    printf("exit_cb\n");
    $exit_cb_called++;
    assert($exit_status == 12, "exit status 12 == " . $exit_status);
    assert($term_signal == 0);
    $loop->close($process, \&close_cb);
}

sub fail_cb {
    my ($process, $exit_status, $term_signal) = @_;
    assert(0, "fail_cb called");
}

sub detach_failure_cb {
    printf("detach_cb\n");
    $exit_cb_called++;
}

sub on_read {
    my ($tcp, $nread, $buf) =@_;
    if ($nread > 0) {
        $output_used += $nread;
    } elsif ($nread < 0) {
        assert($nread == $EOF);
        $loop->close($tcp, \&close_cb);
    }
}

sub on_read_once {
    my ($tcp, $nread, $buf) = @_;
    $loop->read_stop($tcp);
    on_read($tcp, $nread, $buf);
}


sub write_cb {
    my ($req, $status) = @_;
    assert($status == 0);
    $loop->close($req->{handle}, \&close_cb);
}

sub init_process_options {
    my $exit_cb = pop @_;
    $options->{file} = 'perl';
    $options->{args} = \@_;
    $options->{exit_cb} = $exit_cb;
    $options->{flags} = 0;
}


sub timer_counter_cb {
    ++$timer_counter;
}

{
    init_process_options(\&fail_cb);
    $options->{file} = $options->{args}->[0] = "program-that-had-better-not-exist";
    my $ret = $loop->spawn($process, $options);
    assert(!$ret);
    assert($! == ENOENT || $! == EACCES);
    #assert(0 == uv_is_active((uv_handle_t*) &process));
    $loop->close($process, undef);
    $loop->run(RUN_DEFAULT);
}

{
    
    init_process_options("$Bin/spawn/test-sleep.pl", "spawn_helper1", \&exit_cb);
    $loop->spawn($process, $options);
    $loop->timer_init($timer33);
    
    my $times_running = 0;
    $loop->timer_start($timer33, sub{
        print "Hi\n";
        $times_running++;
    }, 10, 10);
    
    $loop->run(RUN_DEFAULT);
    assert($times_running > 10 );
    assert($exit_cb_called == 1);
    assert($close_cb_called == 1);
    done_testing();
}




use strict;
use warnings;
use FindBin '$Bin';

my $TEST_PORT = $ENV{RUM_TEST_PORT} || 9123;
my $pid = 0;
my $killSig = 9;

sub helper_fork_echo_server {
    if ($^O =~ /win/i) {
        $killSig = -9;
        $pid = system (1, "perl", "$Bin/echo-server.pl");
        sleep 1;
    } else {
        $pid = fork();
        if ($pid){
            sleep 1;
        } else {
            exec("perl", "$Bin/echo-server.pl");
            exit;
        }
    }
}

sub helper_kill_echo_server {
    if ($pid) {
        kill $killSig, $pid || die $!;
    }
}

sub helper_test_port { $TEST_PORT }

$SIG{__DIE__} = sub {
    if ($pid) {
        kill $killSig, $pid;
    }
    die $_[0];
};

1;

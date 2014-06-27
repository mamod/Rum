use Rum;
use Data::Dumper;
use Test::More;

use POSIX qw(:errno_h);
my $assert = Require('assert');
my $net = Require('net');
my $common = Require('../common');
my $ROUNDS = 10;
my $ATTEMPTS_PER_ROUND = 10;
my $rounds = 1;
my $reqs = 0;

pummel();

sub pummel {
    diag ('Round ' . $rounds . ' / ' . $ROUNDS . "\n");
  
    for (my $pending = 0; $pending < $ATTEMPTS_PER_ROUND; $pending++) {
        $net->createConnection($common->{PORT})->on('error', sub {
            my $this = shift;
            my $err = shift;
            
            is($err->{errno}, ECONNREFUSED);
            if (--$pending > 0){ return };
            if ($rounds == $ROUNDS) { return check() };
            $rounds++;
            pummel();
        });
        $reqs++;
    }
}

my $check_called = 0;
sub check {
    setTimeout(sub {
        #is(process._getActiveRequests().length, 0);
        #is(process._getActiveHandles().length, 1);    #the timer
        $check_called = 1;
    }, 0);
}


process->on('exit', sub {
    is($rounds, $ROUNDS);
    is($reqs, $ROUNDS * $ATTEMPTS_PER_ROUND);
    ok($check_called);
    done_testing();
});


1;

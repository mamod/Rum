use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;

my $assert = Require('assert');
my $common = Require('../common');
my $fork = Require('child_process')->{fork};


my $cp = $fork->($common->{fixturesDir} . '/child-process-message-and-exit.pl');

my $gotMessage = 0;
my $gotExit = 0;
my $gotClose = 0;

$cp->on('message', sub {
    my $this = shift;
    my $message = shift;
    ok(!$gotMessage);
    ok(!$gotClose);
    is($message, 'hello');
    $gotMessage = 1;
});

$cp->on('exit', sub {
    ok(!$gotExit);
    ok(!$gotClose);
    $gotExit = 1;
});

$cp->on('close', sub {
    ok($gotMessage);
    ok($gotExit);
    ok(!$gotClose);
    $gotClose = 1;
});

process->on('exit', sub {
    ok($gotMessage);
    ok($gotExit);
    ok($gotClose);
    done_testing();
});


1;

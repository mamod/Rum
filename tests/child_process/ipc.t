use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};
my $fork = Require('child_process')->{fork};
my $path = Require('path');

my $sub = $path->join($common->{fixturesDir}, 'echo.pl');

my $gotHelloWorld = 0;
my $gotEcho = 0;

my $child = $spawn->(process->argv->[0], [$sub]);

sub debug {
    print $_[0] . "\n";
}

$child->stderr->on('data', sub {
    my ($this,$data) = @_;
    debug('parent stderr: ' . $data->toString());
});

$child->stdout->setEncoding('utf8');

$child->stdout->on('data', sub {
    my ($this,$data) = @_;
    debug('child said: ' . $data );
    if (!$gotHelloWorld) {
        debug('testing for hello world');
        is("hello world\n", $data);
        $gotHelloWorld = 1;
        debug('writing echo me');
        $child->stdin->write("echo me\n");
    } else {
        debug('testing for echo me');
        is("echo me\n", $data);
        $gotEcho = 1;
        $child->stdin->end();
    }
});

$child->stdout->on('end', sub {
    debug('child end');
});


process->on('exit', sub {
    ok($gotHelloWorld);
    ok($gotEcho);
    done_testing(4);
});

1;

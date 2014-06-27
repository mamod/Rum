use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};
my $path = Require('path');

my $exits = 0;

my $exitScript = $path->join($common->{fixturesDir}, 'exit.pl');
my $exitChild = $spawn->('perl', [$exitScript, 23]);

$exitChild->on('exit', sub {
    my ($this, $code, $signal) = @_;
    is($code, 23);
    ok(!$signal);
    $exits++;
});

my $errorScript = $path->join($common->{fixturesDir},
                            'child_process_should_emit_errors.pl');
my $errorChild = $spawn->('perl', ['runner.pl',$errorScript]);

$errorChild->on('exit', sub {
    my ($this, $code, $signal) = @_;
    ok($code != 0);
    ok(!$signal);
    $exits++;
});

process->on('exit', sub {
    is(2, $exits);
    done_testing();
});

1;

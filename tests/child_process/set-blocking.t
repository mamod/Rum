use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $ch = Require('child_process');
my $path = Require('path');

my $SIZE = 100000;
my $childGone = 0;

my $cp = $ch->spawn('perl', ['-e', 'print "C" x ' . $SIZE . ' . "\n"'], {
    customFds => [0, 1, 2],
    #stdio => 'inherit'
});

#my $cp = $ch->spawn('perl', ['test-inherit.pl'], {
#    customFds => [0, 1, 2],
#    stdio => 'inherit'
#});

$cp->on('exit', sub {
    my $this = shift;
    my $code = shift;
    $childGone = 1;
    is(0, $code);
});

process->on('exit', sub {
    ok($childGone);
    done_testing();
});

1;

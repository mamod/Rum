# > perl runner.pl ./examples/child_process/parent.pl

use Rum;
use Data::Dumper;

my $cp = Require('child_process');

my $n = $cp->fork(__dirname . '/child.pl');

$n->on('message', sub {
    my $this = shift;
    my $m = shift;
    print "parent Got $$\n";
    print Dumper $m;
});

$n->send({ hello => 'world' });

1;

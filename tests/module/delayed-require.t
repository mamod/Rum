use Rum;
use Test::More;

my $a;
setTimeout( sub {
  $a = Require('../fixtures/a');
}, 50);

process->on('exit', sub {
    ok($a->{A});
    is('A', $a->A());
    is('D', $a->D());
    done_testing();
});

1;

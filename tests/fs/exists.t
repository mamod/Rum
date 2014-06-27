use Rum;
use Test::More;

my $fs = Require('fs');
my $f = __filename;
my $exists;
my $doesNotExist;

$fs->exists($f, sub {
    my ($y) = @_;
    $exists = $y;
});

$fs->exists($f . '-NO', sub {
    my $y = shift;
    $doesNotExist = $y;
});

ok($fs->existsSync($f));
ok(!$fs->existsSync($f . '-NO'));

process->on('exit', sub {
    is($exists, 1);
    is($doesNotExist, 0);
    done_testing();
});

1;

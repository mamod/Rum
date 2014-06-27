use Rum;
use Test::More;

my $assert = Require('assert');
my $i;

my $N = 30;
my $done = [];

sub get_printer {
    my $timeout = shift;
    return sub {
        print('Running from setTimeout ' . $timeout . "\n");
        push @{$done}, $timeout;
    };
}

process->nextTick( sub {
    print('Running from nextTick' . "\n");
    push @{$done}, 'nextTick';
});

for ($i = 0; $i < $N; $i += 1) {
    setTimeout(get_printer($i), $i);
}

print('Running from main.' . "\n");


process->on('exit', sub {
    is('nextTick', $done->[0]);
    done_testing();
});

1;

use Rum;
use Test::More;

my $assert = Require('assert');

my $complete = 0;

process->nextTick( sub {
    $complete++;
    process->nextTick( sub {
        $complete++;
        process->nextTick( sub {
            $complete++;
        });
    });
});

setTimeout(sub{
    process->nextTick( sub {
        $complete++;
    });
}, 50);

process->nextTick( sub {
    $complete++;
});

process->on('exit', sub {
    is(5, $complete);
    done_testing();
    process->nextTick(sub {
        die('this should not occur');
    });
});

1;

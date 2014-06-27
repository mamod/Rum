use Rum;
use Test::More;

my $assert = Require('assert');
my @order = ();
process->nextTick( sub{
    setTimeout(sub{
        push @order,('setTimeout');
    }, 0);

    process->nextTick(sub{
        push @order,('nextTick');
    });
});

process->on('exit', sub {
    is_deeply(\@order, ['nextTick', 'setTimeout']);
    done_testing(1);
});
1;

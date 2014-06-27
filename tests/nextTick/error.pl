use Rum;
use Test::More;

my $assert = Require('assert');

my @order;
my $exceptionHandled = 0;

#This nextTick function will throw an error.  It should only be called once.
#When it throws an error, it should still get removed from the queue.
process->nextTick(sub{
  push @order, 'A';
  #cause an error
  what();
});

#This nextTick function should remain in the queue when the first one
#is removed.  It should be called if the error in the first one is
#caught (which we do in this test).
process->nextTick(sub{
    push @order, 'C';
});

process->on('uncaughtException', sub {
    my ($self,$error) = @_;
    if (!$exceptionHandled) {
        $exceptionHandled = 1;
        push @order, 'B';
    } else {
        #If we get here then the first process.nextTick got called twice
        push @order, 'OOPS';
    }
});

process->on('exit', sub {
    
    is_deeply(['A', 'B', 'C'], \@order);
    done_testing();
});

1;

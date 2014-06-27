use strict;
use warnings;
use Rum::Timers;
use Test::More;

{
    my $i = 0;
    my $x = 0;
    for (0..99){
        my $t = ++$i;
        setTimeout(sub{
            is(++$x,$t);
            is($x,$_[1]);
        },100, $i);
    }
}

{
    my $i = 0;
    my $x = 0;
    for (0..99){
        my $t = ++$i;
        my $int; $int = setInterval(sub{
            is(++$x,$t);
            is($x,$_[1]);
            clearInterval($int);
        },100, $i);
    }
}

start_timers();
done_testing(400);

1;

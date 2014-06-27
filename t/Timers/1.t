use strict;
use warnings;
use Rum::Timers;
use Test::More;

##basic tests
my $i = 0;
setTimeout(sub{
    is(1,++$i);
},100);

my $interval = setInterval(sub{
    ++$i;
},100);

clearInterval($interval);

##passing arguments
{
    my $i = 0;
    my $int; $int = setInterval(sub{
        is(0,$_[1]);
        is(1,$_[2]);
        is(2,$_[3]);
        clearInterval($int);
    },100, $i++, $i++, $i++);
}

{
    my $i = 0;
    my $int; $int = setTimeout( sub {
        is(0,$_[1]);
        is(1,$_[2]);
        is(2,$_[3]);
    },100, $i++, $i++, $i++);
}


## 0 timeouts
{
    my $ncalled = 0;
    setTimeout(\&f, 0, 'foo', 'bar', 'baz');
    sub f {
        my ($self, $a, $b, $c) = @_;
        is($a, 'foo');
        is($b, 'bar');
        is($c, 'baz');
        $ncalled++;
    }
    
    setTimeout(sub{
        is($ncalled,1);
    },100);
}

{
    my $ncalled = 0;
    my $iv;
    $iv = setInterval(\&f2, 0, 'foo', 'bar', 'baz');
    sub f2 {
        my ($self, $a, $b, $c) = @_;
        is($a, 'foo');
        is($b, 'bar');
        is($c, 'baz');
        clearTimeout($iv) if (++$ncalled == 3);
    }
    
    setTimeout(sub{
        is($ncalled,3);
    },100);
}

start_timers();
done_testing(21);

1;

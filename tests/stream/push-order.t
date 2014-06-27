use Rum;
use Test::More;

my $Readable = Require('stream')->Readable;

my $s = $Readable->new({
    highWaterMark => 20,
    encoding => 'ascii'
});

my $list = ['1', '2', '3', '4', '5', '6'];

$s->{_read} = sub {
    
    my $one = shift @{$list};
    if (!$one) {
        $s->push(undef);
    } else {
        my $two = shift @{$list};
        $s->push($one);
        $s->push($two);
    }
};

my $v = $s->read(0);

#ACTUALLY [1, 3, 5, 6, 4, 2]

process->on("exit", sub {
    is_deeply($s->{_readableState}->{buffer},['1', '2', '3', '4', '5', '6']);
    done_testing(1);
});
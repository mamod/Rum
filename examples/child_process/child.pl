use Rum;
use Data::Dumper;
process->on('message', sub {
    my $this = shift;
    my $m = shift;
    print "Child got $$\n";
    print Dumper $m;
});

process->send({ foo => 'bar' });

1;

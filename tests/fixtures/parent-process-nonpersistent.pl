use Rum;
use Rum::Loop::Core;
my $spawn = Require('child_process')->{spawn};
my $path = Require('path');
my $childPath = $path->join(__dirname, 'child-process-persistent.pl');
use Data::Dumper;

my $child = $spawn->(process->execPath, [ $childPath ], {
    detached => 1,
    stdio => ['ignore','ignore','ignore']
});


process->stdout->write($child->{pid} . "\n");
$child->unref();

1;

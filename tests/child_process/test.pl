use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;

setInterval(sub{
process->stdout->write(process->argv->[0]);
},10);

1;

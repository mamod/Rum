use Rum;

my $common = Require('../common');
my $assert = Require('assert');

process->stdout->write("hello world\n");

my $stdin = process->openStdin();

$stdin->on('data', sub {
    my $this = shift;
    my $data = shift;
    process->stdout->write($data->toString());
});

1;

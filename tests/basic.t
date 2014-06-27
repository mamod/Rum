use Test::More;
use Rum;
use FindBin qw($Bin);
my $path = Require('path');

###testing dir and file name
{
    my $expected = $path->dirname(__FILE__);
    my $got = __dirname;
    is($got,$expected);
}

{
    my $expected = $path->resolve(__FILE__);
    my $got = __filename;
    is($got,$expected);
}

process->on('exit',sub{
    done_testing(2);
});

1;

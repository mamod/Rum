use Rum;
use Test::More;
use POSIX qw(:errno_h);
my $common = Require('../common');
my $http = Require('http');

my $gotError = 0;

process->on('exit', sub {
    ok($gotError);
    done_testing();
});

sub dontCall {
    fail("should not be called");
}

my $server1 = $http->createServer(\&dontCall);
$server1->listen($common->{PORT}, '127.0.0.1', sub {});
my $server2 = $http->createServer(\&dontCall);
$server2->listen($common->{PORT}, '127.0.0.1', \&dontCall);
$server2->on('error', sub {
    my $this = shift;
    my $e = shift;
    is($e->{errno}, EADDRINUSE);
    $server1->close();
    $gotError = 1;
});

1;

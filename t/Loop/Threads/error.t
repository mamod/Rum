use lib '../../lib';
use lib './lib';
use Test::More;
use warnings;
use strict;
use Rum::Loop;
$Rum::Loop::THREADS = 1;
##should pass on both perl with
##and without threads support
use FindBin qw($Bin);

my $loop = Rum::Loop->new();

my $req = {};
$loop->queue_work($req, {
    args => [1,2,3],
    worker =>  $Bin . '/Worker/02.pl',
    callback => sub {
        my ($error, $req, $args) = @_;
        ok($error && $error =~ /Something went wrong/);
    },
    notify => sub {
        my ($req, $args) = @_;
        fail("should not be called");
    }
});
$loop->run();
done_testing();

1;

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

my @capture;
my $req = {};
$loop->queue_work($req, {
    args => [1,2,3],
    worker =>  $Bin . '/Worker/01.pl',
    callback => sub {
        my ($error, $req, $args) = @_;
        if ($error) {
            fail($error);
        } else {
            is_deeply($args,[4,5,6]);
        }
    },
    notify => sub {
        my ($req, $args) = @_;
        push @capture, $args;
    }
});
$loop->run();

is_deeply \@capture,[1,2,3];
done_testing();

1;

use lib '../../lib';
use lib './lib';
use Test::More;

use warnings;
use strict;
use Rum::Loop;
$Rum::Loop::THREADS = 0;
use FindBin qw($Bin);

my $loop = Rum::Loop->new();
my @capture;

{ #Error
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
}


{ #simple
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
            ok("should be called");
            push @capture, $args;
        }
    });
}

$loop->run();
is_deeply \@capture,[1,2,3];
done_testing();

1;

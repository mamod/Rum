use lib '../../lib';
use lib './lib';
use Test::More;
use warnings;
use strict;
use Rum::Loop;
$Rum::Loop::THREADS = 2;

use Data::Dumper;
use FindBin qw($Bin);

my $loop = Rum::Loop->new();

if( !$Rum::Loop::Pool::threads_enabled ) {
    plan skip_all => 'Not supported on windows';
}

my $timer_counter = 0;
my $t = {};
$loop->timer_init($t);
$loop->timer_start($t, sub{ $timer_counter++ }, 10, 10);

my @nested_capture;
my @timer_capture;
my $req = {};
$loop->queue_work($req, {
    args => [1,2,3],
    worker =>  $Bin . '/Worker/03nested1.pl',
    callback => sub {
        my ($error, $req, $args) = @_;
        if ($error) {
            fail($error);
            $loop->timer_stop($t);
        } else {
            print "NESTED GOT ARGS " . Dumper $args;
            $loop->timer_stop($t);
            is $args,200;
        }
    },
    notify => sub {
        my ($req, $args) = @_;
        if (!ref $args) {
            ok($args =~ /error from nested nested/, $args);
        } elsif ($args->[0] eq 'timer') {
            push @timer_capture, $args->[1];
        } else {
            push @nested_capture, $args->[1];
        }
        
        #print "nested.t notified " . Dumper $args;
    }
});

$loop->run();
is_deeply(\@timer_capture, [1..11]);
is_deeply(\@nested_capture, [2,1,200,201]);
ok($timer_counter > 150);
print Dumper $timer_counter;
done_testing(5);

1;

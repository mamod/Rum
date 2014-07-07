use strict;
use warnings;
use Rum::Loop;
$Rum::Loop::THREADS = 2;

use Data::Dumper;
use FindBin qw($Bin);

my $loop = Rum::Loop->new();
my @capture;

return sub {
    my $req = shift;
    my $args = shift;
    my $timer_count = 0;
    
    my $t = {};
    $loop->timer_init($t);
    $loop->timer_start($t, sub {
        $timer_count++;
        $req->notify(['timer',$timer_count]);
        $loop->timer_stop($t) if $timer_count > 10;
    }, 100, 100);
    
    
    my $return = 0;
    my $req2 = {};
    $loop->queue_work($req2, {
        args => $args,
        worker =>  $Bin . '/Worker/03nested2.pl',
        callback => sub {
            my ($error, $req2, $args) = @_;
            if ($error) {
                die $error;
            }
            print "03.pl got args " . Dumper $args;
            $return = $args;
            my $nested_counter = 2;
            while ($nested_counter--) {
                $req->notify(['nested',$args++]);
                select undef,undef,undef,.2;
            }
        },
        notify => sub {
            my ($req2, $args) = @_;
            $req->notify(['nested',$args]);
        }
    });
    
    my $req3 = {};
    $loop->queue_work($req3, {
        args => $args,
        worker =>  $Bin . '/Worker/03nested_error.pl',
        callback => sub {
            my ($error, $req2, $args) = @_;
            if ($error) {
                $req->notify($error);
                sleep 1; #giv notify some time to be consumed
            }
        }
    });
    
    $loop->run();
    return $return;
};

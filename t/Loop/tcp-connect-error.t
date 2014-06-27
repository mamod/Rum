
use lib './lib';
use lib '../../lib';

use Test::More;
use warnings;
use strict;
use Rum::Loop;
use Rum::Loop::Flags ':Errors';
use Rum::Loop::Utils 'assert';
use POSIX 'errno_h';
use Data::Dumper;

my $loop = Rum::Loop::default_loop();



my $connect_cb_called = 0;
my $close_cb_called = 0;



sub connect_cb {
    my ($handle, $status) = @_;
    assert($handle);
    $connect_cb_called++;
}



sub close_cb {
    my $handle = shift;
    $close_cb_called++;
}

{
    my $garbage = "Bla BLa hhhh hhhhh hhhh bbb bbbb bbb bbbb";
    my $server = {};
    my $req = {};

    $loop->tcp_init($server);
    my $r = $loop->tcp_connect($server,
                     $req,
                     $garbage,
                     \&connect_cb);
    
    ##EINVAL
    ok($! == EINVAL, $!);

    $loop->close($server, \&close_cb);

    $loop->run(RUN_DEFAULT);

    ok($connect_cb_called == 0);
    ok($close_cb_called == 1);

}

done_testing();

use lib './lib';
use strict;
use Data::Dumper;
use IO::Handle;
use Rum::Loop;
use Test::More;

use File::Basename;
my $dirname = dirname(__FILE__);

my $isWin = $^O eq 'MSWin32';

{
    open(my $fh, '>>', undef) or die $!;
    my @args = ("perl","$dirname/exec.pl", fileno $fh);
    ok (system(@args) != 0);
    close $fh;
}


if (!$isWin) {
    open(my $fh, '>>', undef) or die $!;
    Rum::Loop::Core::cloexec($fh,0);
    my @args = ("perl","$dirname/exec.pl", fileno $fh);
    ok(system(@args) == 0 );
    close $fh;
}


{
    open(my $fh, '>>', undef) or die $!;
    ##set and reset
    Rum::Loop::Core::cloexec($fh,0);
    Rum::Loop::Core::cloexec($fh,1);
    my @args = ("perl","$dirname/exec.pl", fileno $fh);
    ok(system(@args) != 0 );   
    close $fh;
}


{
    open(my $fh1, '>>', undef) or die $!;
    $^F = (fileno $fh1) + 5;
    open(my $fh, '>>', undef) or die $!;
    ##set and reset
    Rum::Loop::Core::cloexec($fh,1);
    my @args = ("perl","$dirname/exec.pl", fileno $fh);
    ok(system(@args) != 0 );   
    close $fh1;
    close $fh;
}


if ($isWin) {
    ##set and reset
    Rum::Loop::Core::cloexec(\*STDOUT,1);
    my @args = ("perl","$dirname/exec.pl", fileno *STDOUT);
    ok(system(@args) != 0 );
}

done_testing();


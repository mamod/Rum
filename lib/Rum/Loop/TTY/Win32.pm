package Rum::Loop::TTY::Win32;
use strict;
use warnings;
#use Win32::Console;
#my $CONSOLE = Win32::Console->new();
my $CONSOLE;
sub Rum::Loop::TTY::tty_get_winsize {
    my ($width, $height) = $CONSOLE->Size();
    return ($width, $height);
}

1;

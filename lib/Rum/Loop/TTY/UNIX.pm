package Rum::Loop::TTY::UNIX;
use strict;
use warnings;


sub Rum::Loop::TTY::tty_get_winsize {
    
    require 'sys/ioctl.ph';
    
    my ($rows, $cols, $xpixel, $ypixel);
    my $winsize = "\0" x 8;
    
    if (!defined &TIOCGWINSZ){
        ($rows,$cols) = `stty size`=~/(\d+)\s+(\d+)/?($1,$2):(80,25);
    } else {
        if (ioctl(STDOUT, &TIOCGWINSZ, $winsize)) {
            ($rows, $cols, $xpixel, $ypixel) = unpack('S4', $winsize);
        } else {
            die $!;
            $cols = 80;
        }
    }
    
    return ($cols,$rows);
}

1;

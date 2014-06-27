packahe Rum::Loop::OS;
use strict;
use warnings;

if ($^O =~ /mswin/i) {
    require Rum::Loop::OS::Win32;
} else {
    require Rum::Loop::OS::Posix;
}


sub nonblock {}
sub cloexe   {}
sub loop_io  {}

1;

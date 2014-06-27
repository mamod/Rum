package Rum::Lib::OS;
use Rum qw/module process/;

module->{exports}->{EOL} = process->platform eq 'win32' ? "\r\n" : "\n";


1;

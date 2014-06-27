package Rum::Lib::TTY;
use Rum::TTY::ReadStream;
use Rum::TTY::WriteStream;

use Rum 'module';
module->{exports} = {
    ReadStream => 'Rum::TTY::ReadStream',
    WriteStream => 'Rum::TTY::WriteStream',
};

1;

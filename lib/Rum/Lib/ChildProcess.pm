package Rum::Lib::ChildProcess;
use Rum::ChildProcess;
use Rum 'module';
module->{exports} = {
    fork => \&Rum::ChildProcess::_fork,
    _fork => \&Rum::ChildProcess::_fork,
    spawn => \&Rum::ChildProcess::_spawn,
    exec => \&Rum::ChildProcess::_exec,
    execFile => \&Rum::ChildProcess::_execFile,
    _forkChild => \&Rum::ChildProcess::_forkChild
};

1;

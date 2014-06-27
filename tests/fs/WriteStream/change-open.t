use Rum;
use Test::More;
no warnings 'redefine';
my $common = Require('../../common');
my $assert = Require('assert');

my $path = Require('path');
my $fs = Require('fs');

my $file = $path->join($common->{tmpDir}, 'write.txt');

my $stream = $fs->WriteStream($file);

my $_fs_close = \&Rum::Fs::close;
my $_fs_open = \&Rum::Fs::open;

#change the fs.open with an identical function after the WriteStream
#has pushed it onto its internal action queue, but before it's
#returned.  This simulates AOP-style extension of the fs lib.

*Rum::Fs::open = sub {
    return $_fs_open->(@_);
};

*Rum::Fs::close = sub {
    my ($this,$fd) = @_;
    ok($fd, 'fs.close must not be called with an undefined fd.');
    *Rum::Fs::close = $_fs_close;
    *Rum::Fs::open = $_fs_open;
};

$stream->write('foo');
$stream->end();

process->on('exit', sub {
    is(\&Rum::Fs::open, $_fs_open);
    done_testing(2);
});

1;

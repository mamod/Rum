use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $fork = Require('child_process')->{fork};
my $path = Require('path');

sub debug {
    print STDERR $_[0] . "\n";
}

if (process->argv->[2] && process->argv->[2] eq 'child') {
    debug('child -> call disconnect');
    process->disconnect();
    
    setTimeout(sub {
        debug('child -> will this keep it alive?');
        process->on('message', sub { });
    }, 400);

} else {
    my $child = $fork->(__filename, ['child']);
    
    $child->on('disconnect', sub {
        debug('parent -> disconnect');
    });
    
    $child->once('exit', sub {
        debug('parent -> exit');
        ok(1);
    });
    
    process->on('exit', sub{
        done_testing();
    });
}

1;

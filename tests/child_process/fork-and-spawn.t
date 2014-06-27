use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};
my $fork = Require('child_process')->{fork};
my $path = Require('path');

#Fork, then spawn. The spawned process should not hang.

my $args = process->argv->[2];
my $seenExit = 0;

sub checkExit {
    my $this = shift;
    my $statusCode = shift;
    $seenExit = 1;
    $assert->equal($statusCode, 0);
    process->nextTick(sub {
        
    });
}

sub haveExit {
    $assert->equal($seenExit, 1);
    #done_testing();
}

if (!$args) {
    my $child = $fork->(__filename, ['fork'])->on('exit', \&checkExit);
    process->on('exit', \&haveExit);
    
    $child->on('exit',sub{
        my $this = shift;
        my $code = shift;
        is($code, 0);
        done_testing();
    });
    
} elsif ($args eq 'fork'){
    $spawn->(process->execPath, [__filename, 'spawn'])->on('exit', \&checkExit);
    process->on('exit', \&haveExit);
} elsif ($args eq 'spawn'){
    exit 0;
} else {
    die;
}



1;

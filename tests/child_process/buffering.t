use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};

my $pwd_called = 0;
my $childClosed = 0;
my $childExited = 0;

sub debug {
    process->stderr->write($_[0] . "\n");
}
use Data::Dumper;

sub pwd {
    my ($callback) = @_;
    my $output = '';
    my $child = $common->spawnPwd();
    
    $child->stdout->setEncoding('utf8');
    $child->stdout->on('data', sub {
        my $this = shift;
        my $s = shift;
        #print Dumper $s;
        debug('stdout: ' . $s);
        $output .= $s;
    });

    $child->on('exit', sub {
        my $this = shift;
        my $c = shift;
        debug('exit: ' . $c);
        $assert->equal(0, $c);
        $childExited = 1;
    });
    
    $child->on('close', sub {
        $callback->($output);
        $pwd_called = 1;
        $childClosed = 1;
    });
}


pwd( sub {
    my $result = shift;
    debug($result);
    $assert->ok(length $result > 1);
    my $last = substr $result, -1,1;
    $assert->equal("\n", $last);
});

process->on('exit', sub {
    is(1, $pwd_called);
    is(1, $childExited);
    is(1, $childClosed);
    done_testing();
});

1;

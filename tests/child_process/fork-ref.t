use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;

my $assert = Require('assert');
my $common = Require('../common');
my $fork = Require('child_process')->{fork};



if (process->argv->[2] && process->argv->[2] eq 'child') {
    process->send('1');
    
    #check that child don't instantly die
    setTimeout( sub {
        process->send('2');
    }, 200);
    
    process->on('disconnect', sub {
        process->stdout->write('3');
        #print (fileno *STDOUT);
        #print "3";
    });

} else {
    my $child = $fork->(__filename, ['child'], {silent => 1});
    #process->stdout->write("3");
    #print "d";
    my $ipc = [];
    my $stdout = '';
    
    $child->on('message', sub {
        my $this = shift;
        my $msg = shift;
        push @{$ipc},$msg;
        if ($msg == 2){
            $child->disconnect();
        };
    });
    
    $child->stdout->on('data', sub {
        my $this = shift;
        my $chunk = shift;
        $stdout .= $chunk->toString();
    });
    
    $child->once('exit', sub {
        is_deeply(['1', '2'], $ipc);
        is($stdout, '3');
        done_testing();
    });
}

1;

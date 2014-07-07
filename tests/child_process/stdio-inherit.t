use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;

my $assert = Require('assert');
my $common = Require('../common');
my $spawn = Require('child_process')->{spawn};

if (process->argv->[2] && process->argv->[2] eq 'parent'){
    parent();
} else {
  grandparent();
}

#print Dumper process->execPath;

sub grandparent {
    my $child = $spawn->(process->execPath, [__filename, 'parent']);
    $child->stderr->pipe(process->stderr);
    my $output = '';
    my $input = 'asdfasdf';
    #print Dumper $child;
    $child->stdout->on('data', sub {
        my $this = shift;
        my $chunk = shift;
        #process->stdout->write($chunk);
        $output .= $chunk;
    });
    
    $child->stdout->setEncoding('utf8');
    
    $child->stdin->end($input);
    
    $child->on('close', sub {
        my ($this, $code, $signal) = @_;
        is($code, 0);
        ok(!$signal);
        #cat on windows adds a \r\n at the end.?!
        $output =~ s/(.*)\r\n/$1/; #trim
        $assert->equal($output, $input);
    });
    
    $child->stdout->on('error', sub {
        my ($this, $code, $signal) = @_;
        fail($code);
    });
    
    process->on('exit', sub {
        done_testing();
    });
}

sub parent {
    #should not immediately exit.
    my $child = $common->{spawnCat}->({ stdio => 'inherit' });
}

1;

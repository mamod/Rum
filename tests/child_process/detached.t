use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};
my $path = Require('path');
use POSIX 'close';
my $childPath = $path->join(__dirname, '..', 'fixtures', 'parent-process-nonpersistent.pl');
my $persistentPid = -1;

my $loop = Rum::Loop::default_loop();
my $child = $spawn->(process->execPath, [ $childPath ]);

$child->stdout->on('data', sub {
    my $this = shift;
    my $data = shift;
    
    my @keys = keys %{$loop->{watchers}};
    $persistentPid = $data->toString() + 0;
});

process->on('exit', sub {
    my @keys = keys %{$loop->{watchers}};
    
    ok($persistentPid != -1);
    
    $assert->throws( sub {
        kill -9, $child->{pid} or die $!;
    });
    
    $assert->doesNotThrow( sub {
        kill -9, $persistentPid or die $!;
    });
    
    done_testing();
    
});

1;

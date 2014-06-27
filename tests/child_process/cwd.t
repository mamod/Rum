use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};
my $path = Require('path');

my $returns = 0;

sub debug {
    print $_[0] . "\n";
}
#Spawns 'pwd' with given options, then test
#- whether the exit code equals forCode,
#- optionally whether the stdout result matches forData
#(after removing traling whitespace)

sub testCwd {
    my ($options, $forCode, $forData) = @_;
    my $data = '';
    
    my $child = $common->spawnPwd($options);
    
    $child->stdout->setEncoding('utf8');
    
    $child->stdout->on('data', sub {
        my ($this,$chunk) = @_;
        $data .= $chunk;
    });

    $child->on('exit', sub {
        my ($this, $code, $signal) = @_;
        is($forCode, $code);
    });

    $child->on('close', sub {
        debug($data);
        $data =~ s/[\s\r\n]+$//g;
        $forData && is($forData, $data);
        $returns--;
    });

    $returns++;
    return $child;
}

#Assume these exist, and 'pwd' gives us the right directory back
if (process->platform eq 'win32') {
    testCwd({cwd => process->env->{windir}}, 0, process->env->{windir});
    testCwd({cwd => 'c:\\'}, 0, 'c:\\');
} else {
    testCwd({cwd => '/dev'}, 0, '/dev');
    testCwd({cwd => '/'}, 0, '/');
}

##Assume does-not-exist doesn't exist, expect exitCode=-1 and errno=ENOENT
{
    my $errors = 0;

    testCwd({cwd => 'does-not-exist'}, -1)->on('error', sub {
        my $this = shift;
        my $e = shift;
        is($e->{code}, 'ENOENT');
        $errors++;
    });

    process->on('exit', sub {
        is($errors, 1);
    });
};

#Spawn() shouldn't try to chdir() so this should just work
testCwd(undef, 0);
testCwd({}, 0);
testCwd({cwd => ''}, 0);
testCwd({cwd => undef}, 0);
testCwd({cwd => 0}, 0);

#Check whether all tests actually returned
$assert->notEqual(0, $returns);
process->on('exit', sub {
    is(0, $returns);
    done_testing();
});

1;

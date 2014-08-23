use Rum;

my $path = Require('path');
my $assert = Require('assert');
my $util = Require('util');

exports->{testDir} = $path->dirname(__filename);
exports->{fixturesDir} = $path->join(exports->{testDir}, 'fixtures');
exports->{libDir} = $path->join(exports->{testDir}, '../lib');
exports->{tmpDir} = $path->join(exports->{testDir}, 'tmp');
my $port = process->env->{NODE_COMMON_PORT};
exports->{PORT} = $port ? $port+0 : 12346;

#if (process.platform === 'win32') {
#  exports.PIPE = '\\\\.\\pipe\\libuv-test';
#} else {
#  exports.PIPE = exports.tmpDir + '/test.sock';
#}

exports->{spawnCat} = sub {
    my $options = shift;
    my $spawn = Require('child_process')->{spawn};
    if (process->platform eq 'win32') {
        return $spawn->('more.com', [], $options);
    } else {
        return $spawn->('cat', [], $options);
    }
};

exports->{spawnPwd} = sub {
    my $options = shift;
    my $spawn = Require('child_process')->{spawn};

    if (process->platform eq 'win32') {
        return $spawn->('cmd.exe', ['/c', 'cd'], $options);
    } else {
        return $spawn->('pwd', [], $options);
    }
};


my $mustCallChecks = [];
sub runCallChecks {
    my ($exitCode) = @_;
    if ($exitCode != 0) { return }
    my $failed = $util->filter($mustCallChecks, sub {
        my $context = shift;
        return $context->{actual} ne $context->{expected};
    });
    
    foreach my $context (@{$failed}) {
        printf('Mismatched %s function calls. Expected %d, actual %d.',
        $context->{name},
        $context->{expected},
        $context->{actual});
        #print(context.stack.split('\n').slice(2).join('\n'));
    }
    
    if (scalar @{$failed}) { process->exit(1) };
}

exports->{mustCall} = sub {
    my ($fn, $expected) = @_;
    if (!$util->isNumber($expected)) { $expected = 1 };
    my $context = {
        expected => $expected,
        actual => 0,
        stack => Rum::Error->new(''),
        name => '<anonymous>'
    };
    
    # add the exit listener only once to avoid listener leak warnings
    if (@{$mustCallChecks} == 0) { process->on('exit', \&runCallChecks) }
    push(@{$mustCallChecks}, $context);
    return sub {
        $context->{actual}++;
        return $fn->(@_);
    };
};

1;

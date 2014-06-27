use Rum;

my $path = Require('path');
my $assert = Require('assert');

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
        return $spawn->('cat', [], $options);
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

1;

use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $spawn = Require('child_process')->{spawn};
my $path = Require('path');
my $is_windows = process->platform eq 'win32';

if( $^O =~ /Win32/i ) {
    plan skip_all => 'Not supported on windows';
}

sub debug {
    process->stderr->write($_[0] . "\n");
}

#We're trying to reproduce:
#$ echo "hello\nnode\nand\nworld" | grep o | sed s/o/a/

my ($grep, $sed, $echo);

if (0) {
    $grep = $spawn->('grep', ['--binary', 'o']);
    $sed = $spawn->('sed', ['--binary', 's/o/O/']);
    $echo = $spawn->('cmd.exe',
               ['echo', 'hello&&', 'echo',
                'node&&', 'echo', 'and&&', 'echo', 'world']);
} else {
    $grep = $spawn->('grep', ['o']);
    $sed = $spawn->('sed', ['s/o/O/']);
    $echo = $spawn->('echo', ["hello\nnode\nand\nworld\n"]);
}


#* grep and sed hang if the spawn function leaks file descriptors to child
#* processes.
#* This happens when calling pipe(2) and then forgetting to set the
#* FD_CLOEXEC flag on the resulting file descriptors.
#*
#* This test checks child processes exit, meaning they don't hang like
#* explained above.


#pipe echo | grep
$echo->stdout->on('data', sub {
    my $this = shift;
    my $data = shift;
    debug('grep stdin write ' . $data->length);
    if (!$grep->stdin->write($data)) {
        $echo->stdout->pause();
    }
});

$grep->stdin->on('drain', sub {
    $echo->stdout->resume();
});

#propagate end from echo to grep
$echo->stdout->on('end', sub {
    $grep->stdin->end();
});

$echo->on('exit', sub {
    debug('echo exit');
});

$grep->on('exit', sub {
    debug('grep exit');
});

$sed->on('exit', sub {
    debug('sed exit');
});


#pipe grep | sed
$grep->stdout->on('data', sub {
    my $this = shift;
    my $data = shift;
    debug('grep stdout ' . $data->length);
    if (!$sed->stdin->write($data)) {
        $grep->stdout->pause();
    }
});

$sed->stdin->on('drain', sub {
    $grep->stdout->resume();
});

#propagate end from grep to sed
$grep->stdout->on('end', sub {
    debug('grep stdout end');
    $sed->stdin->end();
});



my $result = '';

#print sed's output
$sed->stdout->on('data', sub {
    my $this = shift;
    my $data = shift;
    $result .= $data->toString('utf8', 0, $data->length);
    debug($data->toString);
});

my $EOL = "\n";
$EOL = "\r\n" if $is_windows;

$sed->stdout->on('end', sub {
    my $this = shift;
    my $data = shift;
    is($result, 'hellO' . $EOL . 'nOde' . $EOL . 'wOrld' . $EOL);
});


process->on('exit', sub {
    done_testing();
});

1;

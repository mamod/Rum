use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $path = Require('path');
my $fs = Require('fs');
my $isWindows = process->platform eq 'win32';
my $openCount = 0;
my $mode;
my $content;

#Removes a file if it exists.
sub removeFile {
    my ($file) = @_;
    return unlink $file;
    try {
        if ($isWindows) {
            $fs->chmodSync($file, 0666);
        }
        unlink($file);
    } catch {
        die $_ if $_;
    };
}
use Data::Dumper;
#Need to hijack fs.open/close to make sure that things
#get closed once they're opened.
sub openSync {
    my $fs = shift;
    $openCount++;
    return $fs->_openSync(@_);
}

sub closeSync {
    my $fs = shift;
    $openCount--;
    return $fs->_closeSync(@_);
}

{
    no strict 'refs';
    no warnings 'redefine';
    *Rum::Fs::_openSync = \&Rum::Fs::openSync;
    *Rum::Fs::openSync = \&openSync;
    *Rum::Fs::_closeSync = \&Rum::Fs::closeSync;
    *Rum::Fs::closeSync = \&closeSync;
}

#Reset the umask for testing
my $mask = process->umask(0000);

#On Windows chmod is only able to manipulate read-only bit. Test if creating
#the file in read-only mode works.
if ($isWindows) {
    $mode = 0444;
} else {
    $mode = 0755;
}

#Test writeFileSync
my $file1 = $path->join($common->{tmpDir}, 'testWriteFileSync.txt');
removeFile($file1);

$fs->writeFileSync( $file1, '123', { mode => $mode} );

$content = $fs->readFileSync($file1, {encoding => 'utf8'});
is('123', $content);

diag("FIXME: permissions test on linux");
# is($mode, $fs->statSync($file1)->{mode} & 0777);

removeFile($file1);

# Test appendFileSync

my $file2 = $path->join($common->{tmpDir}, 'testAppendFileSync.txt');
removeFile($file2);

$fs->appendFileSync($file2, 'abc', {mode => $mode});

my $content2 = $fs->readFileSync($file2, {encoding => 'utf8'});
is('abc', $content2);

diag("FIXME: permissions test on linux");
# is($mode, $fs->statSync($file2)->{mode} & $mode);

removeFile($file2);

#Verify that all opened files were closed.
is(0, $openCount);


process->on('exit', sub {
    done_testing();
});

1;

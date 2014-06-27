use Rum;
use Test::More;

my $Test;
BEGIN {
    eval {
        require Test::Exception;
        Test::Exception->import();
        $Test = 1;
    };
}

if (!$Test){
    plan skip_all => "Test::Exception REQUIRED TO RUN THIS TEST";
}

my $fs = Require('fs');

#####reafFile Check
throws_ok { $fs->readFileSync('./no/file/here') } qr/No such file or directory/;
$fs->readFile('./no/such/file',sub{
    my ($e) = @_;
    ok( $e =~ /No such file or directory/);
});
throws_ok { $fs->readFile(199,sub{}) } qr/path must be a string/;
throws_ok { $fs->readFileSync(199) } qr/path must be a string/;

##write
throws_ok { $fs->writeFile(199,sub{}) } qr/path must be a string/;
throws_ok { $fs->writeFileSync(199) } qr/path must be a string/;

####stats check
throws_ok { $fs->statSync('./oooo') } qr/No such file or directory/;
throws_ok { $fs->statSync(199) } qr/path must be a string/;
throws_ok { $fs->stat(199,sub{}) } qr/path must be a string/;

$fs->stat('./no/such/file',sub{
    my ($e) = @_;
    ok( $e =~ /No such file or directory/);
});

throws_ok { $fs->fstatSync('./oooo') } qr/Bad argument/;
throws_ok { $fs->fstat('./no/such/file',sub{})} qr/Bad argument/;
throws_ok { $fs->fstatSync(199) } qr/bad file descriptor/;

$fs->fstat(188,sub{
    my ($e) = @_;
    ok( $e =~ /bad file descriptor/);
});

##truncate
$fs->truncate(199,sub{
    ok (shift =~ /bad file descriptor/);
});
throws_ok { $fs->ftruncateSync(88) } qr/bad file descriptor/;
throws_ok { $fs->truncateSync(88) } qr/bad file descriptor/;

process->on('exit',sub{
    done_testing(17);
});

1;

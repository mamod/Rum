use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $fs = Require('fs');
my $path = Require('path');

my $filename = $path->join($common->{tmpDir}, 'append.txt');

##diag('appending to ' . $filename);

my $currentFileData = 'ABCD';

my $n = 220;
my $s = '南越国是前203年至前111年存在于岭南地区的一个国家，国都位于番禺，疆域包括今天中国的广东、' .
        '广西两省区的大部份地区，福建省、湖南、贵州、云南的一小部份地区和越南的北部。' .
        '南越国是秦朝灭亡后，由南海郡尉赵佗于前203年起兵兼并桂林郡和象郡后建立。' .
        '前196年和前179年，南越国曾先后两次名义上臣属于西汉，成为西汉的“外臣”。前112年，' .
        '南越国末代君主赵建德与西汉发生战争，被汉武帝于前111年所灭。南越国共存在93年，' .
        '历经五代君主。南越国是岭南地区的第一个有记载的政权国家，采用封建制和郡县制并存的制度，' .
        "它的建立保证了秦末乱世岭南地区社会秩序的稳定，有效的改善了岭南地区落后的政治、##济现状。\n";

my $ncallbacks = 0;

#test that empty file will be created and have content added
$fs->appendFile($filename, $s, sub {
    my $e = shift;
    die $e if $e;

    $ncallbacks++;
    ##diag('appended to file');

    $fs->readFile($filename, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        $ncallbacks++;
        is(bytes::length($s), $buffer->length);
    });
});

#test that appends data to a non empty file
my $filename2 = $path->join($common->{tmpDir}, 'append2.txt');
$fs->writeFileSync($filename2, $currentFileData);

$fs->appendFile($filename2, $s, sub {
    my $e = shift;
    die $e if $e;
    $ncallbacks++;
    #diag('appended to file2');

    $fs->readFile($filename2, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        #diag('file2 read');
        $ncallbacks++;
        is(bytes::length($s) + length($currentFileData), $buffer->length);
    });
});

#test that appendFile accepts buffers
my $filename3 = $path->join($common->{tmpDir}, 'append3.txt');
$fs->writeFileSync($filename3, $currentFileData);

my $buf = Buffer->new($s, 'utf8');
##diag('appending to ' . $filename3);

$fs->appendFile($filename3, $buf, sub {
    my $e = shift;
    die $e if $e;

    $ncallbacks++;
    #diag('appended to file3');

    $fs->readFile($filename3, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        #diag('file3 read');
        $ncallbacks++;
        is($buf->length + length($currentFileData), $buffer->length);
    });
});

#test that appendFile accepts numbers.
my $filename4 = $path->join($common->{tmpDir}, 'append4.txt');
$fs->writeFileSync($filename4, $currentFileData);

#diag('appending to ' . $filename4);

my $m = 0600;
$fs->appendFile($filename4, $n, { mode => $m }, sub {
    my $e = shift;
    die $e if $e;

    $ncallbacks++;
    
    diag("FIXME: permissions test on linux");
    # FIXME: should pass on linux
    #windows permissions aren't unix
    # if (process->platform ne 'win32') {
    #     my $st = $fs->statSync($filename4);
    #     is($st->{mode} & 0700, $m);
    # }

    $fs->readFile($filename4, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        #diag('file4 read');
        $ncallbacks++;
        is(length('' . $n) + length ($currentFileData),$buffer->length);
    });
});

process->on('exit', sub {
    #diag('done');
    #print "called\n"; 
    is(8, $ncallbacks);
  
    unlink($filename);
    unlink($filename2);
    unlink($filename3);
    unlink($filename4);
    
    done_testing();
});

1;

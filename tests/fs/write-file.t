use Rum;
use Rum::Buffer;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $fs = Require('fs');
my $path = Require('path');

my $filename = $path->join($common->{tmpDir}, 'test.txt');

#diag('writing to ' . $filename);

my $n = 220;
my $s = '南越国是前203年至前111年存在于岭南地区的一个国家，国都位于番禺，疆域包括今天中国的广东、' .
        '广西两省区的大部份地区，福建省、湖南、贵州、云南的一小部份地区和越南的北部。' .
        '南越国是秦朝灭亡后，由南海郡尉赵佗于前203年起兵兼并桂林郡和象郡后建立。' .
        '前196年和前179年，南越国曾先后两次名义上臣属于西汉，成为西汉的“外臣”。前112年，' .
        '南越国末代君主赵建德与西汉发生战争，被汉武帝于前111年所灭。南越国共存在93年，' .
        '历经五代君主。南越国是岭南地区的第一个有记载的政权国家，采用封建制和郡县制并存的制度，' .
        "它的建立保证了秦末乱世岭南地区社会秩序的稳定，有效的改善了岭南地区落后的政治、##济现状。\n";

my $ncallbacks = 0;

$fs->writeFile($filename, $s, sub {
    my $e = shift;
    die $e if $e;
    $ncallbacks++;
    #diag('file written');

    $fs->readFile($filename, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        #diag('file read');
        $ncallbacks++;
        is(bytes::length $s, $buffer->length);
    });
});

#test that writeFile accepts buffers
my $filename2 = $path->join($common->{tmpDir}, 'test2.txt');
my $buf = Rum::Buffer->new($s, 'utf8');
#diag('writing to ' . $filename2);

$fs->writeFile($filename2, $buf, sub {
    my $e = shift;
    die $e if $e;
    $ncallbacks++;
    #diag('file2 written');

    $fs->readFile($filename2, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        #diag('file2 read');
        $ncallbacks++;
        is($buf->length, $buffer->length);
    });
});


#test that writeFile accepts numbers.
my $filename3 = $path->join($common->{tmpDir}, 'test3.txt');
#diag('writing to ' . $filename3);

my $m = 0600;
$fs->writeFile($filename3, $n, { mode => $m }, sub {
    my $e = shift;
    die $e if $e;
    
    diag("FIXME: permissions test on linux");
    #windows permissions aren't unix
    if (process->platform ne 'win32') {
        my $st = $fs->statSync($filename3);
        is($st->{mode} & 0600, $m);
    }

    $ncallbacks++;
    #diag('file3 written');
    
    $fs->readFile($filename3, sub {
        my ($e, $buffer) = @_;
        die $e if $e;
        #diag('file3 read');
        $ncallbacks++;
        is( length('' . $n), $buffer->length);
    });
});


process->on('exit', sub {
    #diag('done');
    is(6, $ncallbacks);
    unlink($filename);
    unlink($filename2);
    unlink($filename3);
    done_testing();
});

1;

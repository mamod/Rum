use Rum;
use Test::More;

my $common = Require('../common');
my $assert = Require('assert');
my $path = Require('path');
my $fs = Require('fs');

my $currentFileData = 'ABCD';

my $num = 220;
my $data = '南越国是前203年至前111年存在于岭南地区的一个国家，国都位于番禺，疆域包括今天中国的广东、' .
        '广西两省区的大部份地区，福建省、湖南、贵州、云南的一小部份地区和越南的北部。' .
        '南越国是秦朝灭亡后，由南海郡尉赵佗于前203年起兵兼并桂林郡和象郡后建立。' .
        '前196年和前179年，南越国曾先后两次名义上臣属于西汉，成为西汉的“外臣”。前112年，' .
        '南越国末代君主赵建德与西汉发生战争，被汉武帝于前111年所灭。南越国共存在93年，' .
        '历经五代君主。南越国是岭南地区的第一个有记载的政权国家，采用封建制和郡县制并存的制度，' .
        "它的建立保证了秦末乱世岭南地区社会秩序的稳定，有效的改善了岭南地区落后的政治、##济现状。\n";

#test that empty file will be created and have content added
my $filename = $path->join($common->{tmpDir}, 'append-sync.txt');

#diag('appending to ' . $filename);
$fs->appendFileSync($filename, $data);

my $fileData = $fs->readFileSync($filename);
##diag('filedata is a ' + typeof fileData);

is( bytes::length($data), $fileData->length);

# test that appends data to a non empty file
my $filename2 = $path->join($common->{tmpDir}, 'append-sync2.txt');
$fs->writeFileSync($filename2, $currentFileData);

#diag('appending to ' . $filename2);
$fs->appendFileSync($filename2, $data);

my $fileData2 = $fs->readFileSync($filename2);
is( bytes::length($data) + length($currentFileData) ,  $fileData2->length);

#test that appendFileSync accepts buffers
my $filename3 = $path->join($common->{tmpDir}, 'append-sync3.txt');
$fs->writeFileSync($filename3, $currentFileData);

#diag('appending to ' . $filename3);

my $buf = Buffer->new($data, 'utf8');

$fs->appendFileSync($filename3, $buf);

my $fileData3 = $fs->readFileSync($filename3);

is ($buf->length + length($currentFileData), $fileData3->length);

my $m = 0600;
#test that appendFile accepts numbers.
my $filename4 = $path->join($common->{tmpDir}, 'append-sync4.txt');
$fs->writeFileSync($filename4, $currentFileData, { mode => $m });

#diag('appending to ' . $filename4);

$fs->appendFileSync($filename4, $num, { mode => $m });

diag("FIXME: permissions test on linux");
# FIXME: should pass on linux
#windows permissions aren't unix
# if (process->platform ne 'win32') {
#     my $st = $fs->statSync($filename4);
#     is($st->{mode} & 0700, $m);
# }

my $fileData4 = $fs->readFileSync($filename4);

is( bytes::length("$num") + length($currentFileData),$fileData4->length);

#//exit logic for cleanup
process->on('exit',sub{
    unlink($filename);
    unlink($filename2);
    unlink($filename3);
    unlink($filename4);
    done_testing();
});

1;

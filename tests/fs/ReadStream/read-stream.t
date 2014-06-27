use Rum;
use Data::Dumper;
my $common = Require('../../common');
my $assert = Require('assert');
use Test::More;


#TODO Improved this test. test_ca.pem is too small. A proper test would
#great a large utf8 (with multibyte chars) file and stream it in,
#performing sanity checks throughout.
my $utils = Require('util');
my $path = Require('path');
my $fs = Require('fs');
my $fn = $path->join($common->{fixturesDir}, 'elipses.txt');
my $rangeFile = $path->join($common->{fixturesDir}, 'x.txt');

my $callbacks = { open => 0, end => 0, close => 0 };

my $paused = 0;

my $file = $fs->ReadStream($fn);

$file->on('open',  sub {
    my ($self,$fd) = @_;
    $file->{length} = 0;
    $callbacks->{open}++;
    ok($utils->isNumber($fd));
    ok($file->{readable});

    #// GH-535
    $file->pause();
    $file->resume();
    $file->pause();
    $file->resume();
});

$file->on('data', sub {
    my ($self,$data) = @_;
    ok(ref $data eq 'Rum::Buffer');
    ok(!$paused);
    $file->{length} += $data->length;
    
    $paused = 1;
    $file->pause();
    
    setTimeout( sub {
        $paused = 0;
        $file->resume();
    }, 10);
});


$file->on('end', sub {
    $callbacks->{end}++;
});

$file->on('close', sub {
  $callbacks->{close}++;
  #//assert.equal(fs.readFileSync(fn), fileContent);
});

my $file3 = $fs->createReadStream($fn, {encoding => 'utf8'});
$file3->{length} = 0;
$file3->on('data', sub {
    my ($this,$data) = @_;
    is('string', $utils->typeof($data));
    
    $file3->{length} += length $data;
    
    my @data = split //, $data;
    my $c = chr 0x2026;
    foreach my $char (@data) {
        ##running this test throw assert is much faster
        #http://www.fileformat.info/info/unicode/char/2026/index.htm
        $assert->equal($c, $char);
    }
});

$file3->on('close', sub {
    $callbacks->{close}++;
});

process->on('exit', sub {
    is(1, $callbacks->{open});
    is(1, $callbacks->{end});
    is(2, $callbacks->{close});
    is(30000, $file->{length});
    is(10000, $file3->{length});
});

my $file4 = $fs->createReadStream($rangeFile, {bufferSize => 1, start => 1, end => 2});
my $contentRead = '';
$file4->on('data', sub {
    my ($this,$data) = @_;
    $contentRead .= $data->toString('utf-8');
});

$file4->on('end', sub {
    my ($this,$data) = @_;
    is($contentRead, 'yz');
});


my $file5 = $fs->createReadStream($rangeFile, {bufferSize => 1, start => 1});
$file5->{data} = '';

$file5->on('data',  sub {
    my ($this,$data) = @_;
    $file5->{data} .= $data->toString('utf-8');
});

$file5->on('end', sub {
    is($file5->{data}, "yz\n");
});

#
#// https://github.com/joyent/node/issues/2320
my $file6 = $fs->createReadStream($rangeFile, {bufferSize => 1.23, start => 1});
$file6->{data} = '';
$file6->on('data', sub {
    my ($this,$data) = @_;
    $file6->{data} .= $data->toString('utf-8');
});

$file6->on('end', sub {
    is($file6->{data}, "yz\n");
});


$assert->throws( sub{
    $fs->createReadStream($rangeFile, {start => 10, end => 2});
}, qr/start must be <= end/);

my $stream = $fs->createReadStream($rangeFile, { start => 0, end => 0 });
$stream->{data} = '';

$stream->on('data', sub {
    my ($this,$chunk) = @_;
    $stream->{data} .= $chunk->toString();
});

$stream->on('end', sub {
    is('x', $stream->{data});
});

#pause and then resume immediately.
my $pauseRes = $fs->createReadStream($rangeFile);
$pauseRes->pause();
$pauseRes->resume();
use Data::Dumper;
my $file7 = $fs->createReadStream($rangeFile, { autoClose => 0 });

$file7->on('data', sub {});
$file7->on('end', sub {
    process->nextTick( sub {
        ok(!$file7->{closed});
        ok(!$file7->{destroyed});
        file7Next();
    });
});

sub file7Next {
    #This will tell us if the fd is usable again or not.
    $file7 = $fs->createReadStream(undef, {fd => $file7->{fd}, start => 0 });
    $file7->{data} = '';
    
    $file7->on('data', sub {
        my ($this,$data) = @_;
        $file7->{data} .= $data->toString();
    });
    
    $file7->on('end', sub {
        is($file7->{data}, "xyz\n");
    });
}

#Just to make sure autoClose won't close the stream because of error.
my $mustBeCalled = 0;
my $file8 = $fs->createReadStream(undef, { fd => 13337, autoClose => 0 });
$file8->on('data', sub {});
$file8->on('error', sub{
    ##must be called
    ++$mustBeCalled;
});


#Make sure stream is destroyed when file does not exist.
my $file9 = $fs->createReadStream('/path/to/file/that/does/not/exist');
$file9->on('data', sub {});
$file9->on('error', sub {
    ++$mustBeCalled;
});

process->on('exit', sub {
    
    is($mustBeCalled,2);
    
    ok($file7->{closed});
    ok($file7->{destroyed});
  
    ok(!$file8->{closed});
    ok(!$file8->{destroyed});
    ok($file8->{fd});
  
    ok(!$file9->{closed});
    ok($file9->{destroyed});
    done_testing();
});

1;

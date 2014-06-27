use Rum;

my $common = Require('../common');
my $fs = Require('fs');
my $assert = Require('assert');
my $path = Require('path');

my $filename = $path->join($common->{tmpDir}, 'out.txt');

try {
    $fs->unlinkSync($filename);
} catch {
    #might not exist, that's okay.
};

my $fd = $fs->openSync($filename, 'w');

my $line = "aaaaaaaaaaaaaaaaaaaaaaaaaaaa\n";

my $N = 10240;
my $complete = 0;

for (my $i = 0; $i < $N; $i++) {
    #Create a new buffer for each write. Before the write is actually
    #executed by the thread pool, the buffer will be collected.
    my $buffer = Buffer->new($line);
    $fs->write($fd, $buffer, 0, $buffer->length, undef, sub {
        my ($er, $written) = @_;
        $complete++;
        if ($complete == $N) {
            $fs->closeSync($fd);
            my $s = $fs->createReadStream($filename);
            $s->on('data', \&testBuffer);
        }
    });
}

my $bytesChecked = 0;

sub testBuffer {
    my ($this,$b) = @_;
    for (my $i = 0; $i < $b->length; $i++) {
        $bytesChecked++;
        if ($b->get($i) != ord 'a' && $b->get($i) != ord "\n" ) {
            die('invalid char ' . $i .  $b->[$i]);
        }
    }
}

process->on('exit', sub {
    #Probably some of the writes are going to overlap, so we can't assume
    #that we get (N * line.length). Let's just make sure we've checked a
    #few...
    $assert->ok($bytesChecked > 1000);
});

1;

use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $BUFSIZE = 1024;

use IO::Handle;

STDIN->autoflush(1);
STDOUT->autoflush(1);

sub debug {
    print($_[0]);
}

my $switch = process->argv->[2] || ''; 
if (!$switch) {
    return parent();
} elsif ($switch eq 'child'){
    return child();
} else {
    die ('wtf?');
}

sub parent {
    my $spawn = Require('child_process')->{spawn};
    my $child = $spawn->(process->execPath, [__filename, 'child'],{
        #stdio => ['pipe','pipe','inherit']
    });
    my $sent = 0;
    
    my $n = 0;
    $child->stdout->setEncoding('ascii');
    $child->stdout->on('data', sub {
        my $this = shift;
        my $c = shift;
        $n += $c;
    });
    
    $child->stdout->on('end', sub {
        is(+$n, $sent);
        done_testing;
        #debug('ok2');
    });
    
    #Write until the buffer fills up.
    my $buf;
    do {
        $buf = Buffer->new($BUFSIZE);
        $buf->fill('.');
        $sent += $BUFSIZE;
        print Dumper $sent;
    } while ($child->stdin->write($buf));
    
    #then write a bunch more times.
    for (my $i = 0; $i < 100; $i++) {
        my $buf = Buffer->new($BUFSIZE);
        $buf->fill('.');
        $sent += $BUFSIZE;
        $child->stdin->write($buf);
    }
    
    #now end, before it's all flushed.
    $child->stdin->end();
    
    1;
}

sub child {
    my $received = 0;
    process->stdin->on('data', sub {
        my $this = shift;
        my $c = shift;
        $received += $c->length();
    });
    
    process->stdin->on('end', sub {
        debug($received);
    });
    
    1;
}

1;

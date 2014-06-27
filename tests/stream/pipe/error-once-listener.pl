use Rum;

my $common = Require('../../common');
my $assert = Require('assert');

my $util = Require('util');
my $stream = Require('stream');

my $read = Read->new();
my $write = Write->new();

$write->once('error', sub {});
$write->once('alldone', sub {
    print('ok' . "\n");
});

process->on('exit', sub {
    print('error thrown even with listener');
});

$read->pipe($write);

package Read; {
    use base 'Rum::Stream::Readable';
    sub new {
        my $this = bless {}, shift;
        $this->SUPER::new();
    }
    
    sub _read {
        my $this = shift;
        $this->push('x');
        $this->push(undef);
    }
    
}

package Write; {
    use base 'Rum::Stream::Writable';
    use Rum::Error;
    sub new {
        my $this = bless {}, shift;
        $this->SUPER::new();
    }
    
    sub _write {
        my ($this, $buffer, $encoding, $cb) = @_;
        $this->emit('error', Rum::Error->new('boom'));
        $this->emit('alldone');
    }
}

1;

package Rum::Fs::WriteStream;
use Rum;
use Rum::Utils;
use Rum::Buffer;
use base 'Rum::Stream::Writable';
my $util = 'Rum::Utils';
my $fs = 'Rum::Fs';

sub new {
    my ($class, $path, $options) = @_;
    my $this = ref $class ? $class : bless {}, $class;
    
    $options ||= {};
    
    $this->SUPER::new($options);
    
    $this->{path} = $path;
    $this->{fd} = undef;
    
    $this->{fd} =  $options->{fd};
    $this->{flags} = defined $options->{flags} ? $options->{flags} : 'w';
    $this->{mode} = defined $options->{mode} ? $options->{mode} : 438;
    
    $this->{start} = defined $options->{start} ? $options->{start} : undef;
    $this->{pos} = undef;
    $this->{bytesWritten} = 0;
    
    if (defined $this->{start} ) {
        if (!$util->isNumber($this->{start})) {
            Carp::croak('start must be a Number');
        }
        if ($this->{start} < 0) {
            Carp::croak('start must be >= zero');
        }
        
        $this->{pos} = $this->{start};
    }
    
    if (!$util->isNumber($this->{fd})) {
        $this->open();
    }
    
    #dispose on finish.
    $this->once('finish', sub{
        $this->close();
    });
    
    return $this;
}

sub open {
    my $this = shift;
    $fs->open($this->{path}, $this->{flags}, $this->{mode}, sub {
        my ($er, $fd) = @_;
        if ($er) {
            $this->destroy();
            $this->emit('error', $er);
            return;
        }
        
        $this->{fd} = $fd;
        $this->emit('open', $fd);
    });
}

sub _write {
    my ($this, $data, $encoding, $cb) = @_;
    
    if (!$util->isBuffer($data)) {
        return $this->emit('error', Rum::Error->new('Invalid data'));
    }
    
    if (!$util->isNumber($this->{fd} )) {
        return $this->once('open', sub{
            $this->_write($data, $encoding, $cb);
        });
    }
    
    $fs->write($this->{fd}, $data, 0, $data->length, $this->{pos}, sub {
        my ($er, $bytes) = @_;
        if ($er) {
            $this->destroy();
            return $cb->($er);
        }
        $this->{bytesWritten} += $bytes;
        $cb->();
    });

    if ( defined $this->{pos} ) {
        $this->{pos} += $data->length;
    }
    
    return $this;
}


*destroy = \&Rum::Fs::ReadStream::destroy;
*close = \&Rum::Fs::ReadStream::close;
*destroySoon = \&Rum::Stream::Writable::end;

1;

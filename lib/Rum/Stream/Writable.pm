package Rum::Stream::Writable;
use lib '../../';

use warnings;
use strict;
use Rum;
use Rum::Utils;
use Rum::Error;
use Rum::Buffer;

use base 'Rum::Stream';
my $util = 'Rum::Utils';
use Data::Dumper;

sub _WriteReq {
    my ($chunk, $encoding, $cb) = @_;
    my $this = {};
    $this->{chunk} = $chunk;
    $this->{encoding} = $encoding;
    $this->{callback} = $cb;
    return $this;
}

sub new {
    my ($class,$options) = @_;
    #Writable ctor is applied to Duplexes, though they're not
    #instanceof Writable, they're instanceof Readable.
    my $this = ref $class ? $class : bless {}, $class;
    
    $this->{_writableState} = Rum::Stream::Writable::State->new($options, $this);
    
    #legacy.
    $this->{writable} = 1;
    Rum::Stream::new($this);
    return $this;
}

#Otherwise people can pipe Writable streams, which is just wrong.
sub pipe {
    my $this = shift;
    $this->emit('error', Rum::Error->new('Cannot pipe. Not readable.'));
}

sub writeAfterEnd {
    my ($stream, $state, $cb) = @_;
    my $er = Rum::Error->new('write after end');
    #TODO: defer error events consistently everywhere, not just the cb
    $stream->emit('error', $er);
    process->nextTick( sub {
        $cb->($er);
    });
}

#If we get something that is not a buffer, string, null, or undefined,
#and we're not in objectMode, then that's an error.
#Otherwise stream chunks are all considered to be of length=1, and the
#watermarks determine how many objects to keep in the buffer, rather than
#how many bytes or characters.
sub validChunk {
    my ($stream, $state, $chunk, $cb) = @_;
    my $valid = 1;
    if (!$util->isBuffer($chunk) &&
    !$util->isString($chunk) &&
    !$util->isNullOrUndefined($chunk) &&
    !$state->{objectMode} ) {
        my $er = Rum::Error->new('Invalid non-string/buffer chunk');
        $stream->emit('error', $er);
        process->nextTick( sub {
            $cb->($er);
        });
        $valid = 0;
    }
    return $valid;
}

sub write {
    my ($this, $chunk, $encoding, $cb) = @_;
    my $state = $this->{_writableState};
    my $ret = 0;
    
    if (ref $encoding eq 'CODE') {
        $cb = $encoding;
        $encoding = undef;
    }

    if ($util->isBuffer($chunk)) {
        $encoding = 'buffer';
    } elsif (!$encoding) {
        $encoding = $state->{defaultEncoding};
    }
    
    $cb = sub {} if ( ref $cb ne 'CODE' ); 

    if ($state->{ended}) {
        writeAfterEnd($this, $state, $cb);
    } elsif (validChunk($this, $state, $chunk, $cb)) {
        $state->{pendingcb}++;
        $ret = writeOrBuffer($this, $state, $chunk, $encoding, $cb);
    }

    return $ret;
}

sub cork {
    my $state = shift->{_writableState};
    $state->{corked}++;
}

sub uncork {
    my $this = shift;
    my $state = $this->{_writableState};
    
    if ($state->{corked}) {
        $state->{corked}--;
        if (!$state->{writing} &&
        !$state->{corked} &&
        !$state->{finished} &&
        !$state->{bufferProcessing} &&
        scalar @{$state->{buffer}} ) {
            clearBuffer($this, $state);
        }
    }
}

sub decodeChunk {
    my ($state, $chunk, $encoding) = @_;
    if (!$state->{objectMode} &&
      $state->{decodeStrings} &&
      $util->isString($chunk)) {
        $chunk = Rum::Buffer->new($chunk, $encoding);
    }
    return $chunk;
}


#if we're already writing something, then just put this
#in the queue, and wait our turn.  Otherwise, call _write
#If we return false, then we need a drain event, so set that flag.
sub writeOrBuffer {
    my ($stream, $state, $chunk, $encoding, $cb) = @_;
    $chunk = decodeChunk($state, $chunk, $encoding);
    if ($util->isBuffer($chunk)) {
        $encoding = 'buffer';
    }
    
    my $len = $state->{objectMode} ? 1 : _getLength($chunk);
    
    $state->{length} += $len;

    my $ret = $state->{length} < $state->{highWaterMark};
    $state->{needDrain} = !$ret;
    if ($state->{writing} || $state->{corked}) {
        push @{ $state->{buffer} }, _WriteReq($chunk, $encoding, $cb);
    } else {
        doWrite($stream, $state, 0, $len, $chunk, $encoding, $cb);
    }
    return $ret;
}

sub doWrite {
    my ($stream, $state, $writev, $len, $chunk, $encoding, $cb)  = @_;
    $state->{writelen} = $len;
    $state->{writecb} = $cb;
    $state->{writing} = 1;
    $state->{sync} = 1;
    if ($writev) {
        $stream->_writev($chunk, $state->{onwrite});
    } else {
        $stream->_write($chunk, $encoding, $state->{onwrite});
    }
    $state->{sync} = 0;
}

sub onwriteError {
    my ($stream, $state, $sync, $er, $cb) = @_;
    if ($sync) {
        process->nextTick(sub {
            $state->{pendingcb}--;
            $cb->($er);
        });
    } else {
        $state->{pendingcb}--;
        $cb->($er);
    }

    $stream->emit('error', $er);
}

sub onwriteStateUpdate {
    my ($state) = @_;
    $state->{writing} = 0;
    $state->{writecb} = undef;
    $state->{length} -= $state->{writelen};
    $state->{writelen} = 0;
}

sub onwrite {
    my ($stream, $er) = @_;
    my $state = $stream->{_writableState};
    my $sync = $state->{sync};
    my $cb = $state->{writecb};
    
    onwriteStateUpdate($state);
    
    if ($er) {
        my @c = caller();
        onwriteError($stream, $state, $sync, $er, $cb);
    } else {
        #Check if we're actually ready to finish, but don't emit yet
        my $finished = needFinish($stream, $state);
        
        if (!$finished &&
        !$state->{corked} &&
        !$state->{bufferProcessing} &&
        scalar @{$state->{buffer}} ) {
            clearBuffer($stream, $state);
        }
        
        if ($sync) {
            #afterWrite($stream,$state, $finished, $cb);
            Rum::process->nextTick( sub {
                afterWrite($stream, $state, $finished, $cb);
            });
        } else {
            $stream->afterWrite($state, $finished, $cb);
        }
    }
}

sub afterWrite {
    my ($stream, $state, $finished, $cb) = @_;
    if (!$finished) {
        onwriteDrain($stream, $state);
    }
    
    $state->{pendingcb}--;
    $cb->();
    finishMaybe($stream, $state);
}

#Must force callback to be called on nextTick, so that we don't
#emit 'drain' before the write() consumer gets the 'false' return
#value, and has a chance to attach a 'drain' listener.
sub onwriteDrain {
    my ($stream, $state) = @_;
    if ($state->{length} == 0 && $state->{needDrain} ) {
        $state->{needDrain} = 0;
        $stream->emit('drain');
    }
}


#if there's something in the buffer waiting, then process it
sub clearBuffer {
    my ($stream, $state) = @_;
    $state->{bufferProcessing} = 1;
    
    if ($stream->{_writev} && scalar @{ $state->{buffer} } > 1) {
        #Fast case, write everything using _writev()
        my @cbs;
        foreach my $buf ( @{$state->{buffer}} ) {
            push @cbs, $buf->{callback};
        }
        
        #count the one we are adding, as well.
        #TODO(isaacs) clean this up
        $state->{pendingcb}++;
        doWrite($stream, $state, 1, $state->{length}, $state->{buffer}, '', sub {
            my $err = shift;
            foreach my $cb (@cbs) {
                $state->{pendingcb}--;
                $cb->($err);
            }
        });
        
        #Clear buffer
        $state->buffer = [];
    } else {
        #Slow case, write chunks one-by-one
        my $c;
        for ($c = 0; $c < scalar @{$state->{buffer}}; $c++) {
            
            my $entry = $state->{buffer}->[$c];
            my $chunk = $entry->{chunk};
            my $encoding = $entry->{encoding};
            my $cb = $entry->{callback};
            my $len = $state->{objectMode} ? 1 : _getLength($chunk);
            
            doWrite($stream, $state, 0, $len, $chunk, $encoding, $cb);
            
            #if we didn't call the onwrite immediately, then
            #it means that we need to wait until it does.
            #also, that means that the chunk and cb are currently
            #being processed, so move the buffer counter past them.
            if ($state->{writing}) {
                $c++;
                last;
            }
        }
        
        if ($c < scalar @{ $state->{buffer} } ){
            $state->{buffer} = [splice @{$state->{buffer}}, $c];
        } else {
            #$state->{buffer}->{length} = 0;
            $state->{buffer} = [];
        }
    }

    $state->{bufferProcessing} = 0;
}

sub _write  {
    my ($this, $chunk, $encoding, $cb) = @_;
    if ($this->{_write} && ref $this->{_write} eq 'CODE') {
        return $this->{_write}->(@_);
    }
    $cb->(Rum::Error->new('not implemented'));
}

sub end {
    my ($this, $chunk, $encoding, $cb) = @_;
    my $state = $this->{_writableState};

    if (ref $chunk eq 'CODE') {
        $cb = $chunk;
        $chunk = undef;
        $encoding = undef;
    } elsif (ref $encoding eq 'CODE') {
        $cb = $encoding;
        $encoding = undef;
    }

    if (!$util->isNullOrUndefined($chunk)){
        $this->write($chunk, $encoding);
    }
    
    #.end() fully uncorks
    if ($state->{corked}) {
        $state->{corked} = 1;
        $this->uncork();
    }

    #ignore unnecessary end() calls.
    if (!$state->{ending} && !$state->{finished}){
        endWritable($this, $state, $cb);
    }
}

sub needFinish {
    my ($stream, $state) = @_;
    return ($state->{ending} &&
          $state->{length} == 0 &&
          !$state->{finished} &&
          !$state->{writing});
}

sub prefinish {
    my ($stream, $state) = @_;
    if (!$state->{prefinished}) {
        $state->{prefinished} = 1;
        $stream->emit('prefinish');
    }
}

sub finishMaybe {
    my ($stream, $state) = @_;
    my $need = needFinish($stream, $state);
    if ($need) {
        if ($state->{pendingcb} == 0) {
            prefinish($stream, $state);
            $state->{finished} = 1;
            $stream->emit('finish');
        } else {
            prefinish($stream, $state);
        }
    }
    return $need;
}

sub endWritable {
    my ($stream, $state, $cb) = @_;
    $state->{ending} = 1;
    finishMaybe($stream, $state);
    if ($cb) {
        if ( $state->{finished} ) {
            process->nextTick($cb);
        } else {
            $stream->once('finish', $cb);
        }
    }
    $state->{ended} = 1;
}

##get length of either buffer or string
sub _getLength {
    return !ref $_[0] ? length $_[0] : $_[0]->length;
}

package Rum::Stream::Writable::State; {
    use strict;
    use warnings;
    use Data::Dumper;
    sub new {
        my ($class, $options, $stream) = @_;
        $options = $options || {};
        
        my $this = ref $class ? $class : bless {}, $class;
        #the point at which write() starts returning false
        #Note: 0 is a valid value, means that we always return false if
        #the entire buffer is not flushed immediately on write()
        my $hwm = $options->{highWaterMark};
        my $defaultHwm = $options->{objectMode} ? 16 : 16 * 1024;
        $this->{highWaterMark} = !defined $hwm ?  $defaultHwm : $hwm;
        
        #object stream flag to indicate whether or not this stream
        #contains buffers or objects.
        $this->{objectMode} = !!$options->{objectMode};
        
        #cast to ints.
        $this->{highWaterMark} = ~~$this->{highWaterMark};
        
        $this->{needDrain} = 0;
        #at the start of calling end()
        $this->{ending} = 0;
        #when end() has been called, and returned
        $this->{ended} = 0;
        #when 'finish' is emitted
        $this->{finished} = 0;
        
        #should we decode strings into buffers before passing to _write?
        #this is here so that some node-core streams can optimize string
        #handling at a lower level.
        my $noDecode = !defined $options->{decodeStrings} ? 0 : $options->{decodeStrings} == 0;
        $this->{decodeStrings} = !$noDecode;
        
        #Crypto is kind of old and crusty.  Historically, its default string
        #encoding is 'binary' so we have to make this configurable.
        #Everything else in the universe uses 'utf8', though.
        $this->{defaultEncoding} = $options->{defaultEncoding} || 'utf8';
        
        #not an actual buffer we keep track of, but a measurement
        #of how much we're waiting to get pushed to some underlying
        #socket or file.
        $this->{length} = 0;
        
        #a flag to see when we're in the middle of a write.
        $this->{writing} = 0;
        
        #when true all writes will be buffered until .uncork() call
        $this->{corked} = 0;
        
        #a flag to be able to tell if the onwrite cb is called immediately,
        #or on a later tick.  We set this to true at first, because any
        #actions that shouldn't happen until "later" should generally also
        #not happen before the first write call.
        $this->{sync} = 1;
        
        #a flag to know if we're processing previously buffered items, which
        #may call the _write() callback in the same tick, so that we don't
        #end up in an overlapped onwrite situation.
        $this->{bufferProcessing} = 0;
        
        #the callback that's passed to _write(chunk,cb)
        $this->{onwrite} = sub {
            my ($r,$er) = @_;
            Rum::process->nextTick(sub{
                Rum::Stream::Writable::onwrite($stream, $er);
            });
        };
        
        #the callback that the user supplies to write(chunk,encoding,cb)
        $this->{writecb} = undef;
        
        #the amount that is being written when _write is called.
        $this->{writelen} = 0;
        
        $this->{buffer} = [];
        
        #number of pending user-supplied write callbacks
        #this must be 0 before 'finish' can be emitted
        $this->{pendingcb} = 0;
        
        #emit prefinish if the only thing we're waiting for is _write cbs
        #This is relevant for synchronous Transform streams
        $this->{prefinished} = 0;
        
        return $this;
    }
    
    sub onwrite {
        shift->{onwrite}->();
    }
}

1;

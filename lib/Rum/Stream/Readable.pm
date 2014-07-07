package Rum::Stream::Readable;
use lib '../../';
use warnings;
use strict;
use Rum 'process';
use List::Util qw(min);
use Rum::Utils;
use Rum::Error;
use Rum::Buffer;

use base qw(Rum::Stream);
my $util = 'Rum::Utils';
use Data::Dumper;

my $step = 0;
sub debug {
    return;
    print "STRAM $$: (" . $step++ . ") : ";
    for (@_){
        if (ref $_){
            print Dumper $_;
        } elsif (defined $_) {
            print $_ . " ";
        } else {
            print "undefined ";
        }
    }
    print "\n";
}

sub new {
    my ($class,$options) = @_;
    my $this = ref $class ? $class : bless {}, $class;
    $this->{_readableState} = Rum::Stream::Readable::State->new($options, $this);
    $this->{readable} = 1;
    Rum::Stream::new($this);
    return $this;
}

sub readableAddChunk {
    my ($stream, $state, $chunk, $encoding, $addToFront) = @_;
    my $er = chunkInvalid($state, $chunk);
    if ($er) {
        $stream->emit('error', $er);
    } elsif ( $util->isNullOrUndefined($chunk) ) {
        $state->{reading} = 0;
        onEofChunk($stream, $state) if (!$state->{ended});
    } elsif ($state->{objectMode} || $chunk && _getObjLength($chunk) > 0) {
        if ($state->{ended} && !$addToFront) {
            my $e = Rum::Error->new('stream->push() after EOF');
            $stream->emit('error', $e);
        } elsif ($state->{endEmitted} && $addToFront) {
            my $e = Rum::Error->new('stream.unshift() after end event');
            $stream->emit('error', $e);
        } else {
            if ($state->{decoder} && !$addToFront && !$encoding) {
                $chunk = $state->{decoder}->write($chunk);
            }
            $state->{reading} = 0 if !$addToFront;
            #if we want the data now, just emit it.
            if ( $state->{flowing} && $state->{length} == 0 && !$state->{sync} ) {
                $stream->emit('data', $chunk);
                $stream->read(0);
            } else {
                #update the buffer info.
                $state->{length} += $state->{objectMode} ? 1 : _getLength($chunk);
                if ($addToFront) {
                    unshift @{ $state->{buffer} },$chunk;
                } else {
                    CORE::push @{ $state->{buffer} },$chunk;
                }
                
                emitReadable($stream) if $state->{needReadable};
            }
            maybeReadMore($stream, $state);
        }
    } elsif (!$addToFront) {
        $state->{reading} = 0;
    }
    
    return needMoreData($state);
}

#you can override either this method, or the async _read(n) below.
sub read {
    my ($this,$n) = @_;
    debug('read', $n);
    my $state = $this->{_readableState};
    my $nOrig = $n;

    if (!$util->isNumber($n) || $n > 0){
        $state->{emittedReadable} = 0;
    }

    #if we're doing read(0) to trigger a readable event, but we
    #already have a bunch of data in the buffer, then just trigger
    #the 'readable' event and move on.
    if ( defined $n && $n == 0 &&
    $state->{needReadable} &&
    ($state->{length} >= $state->{highWaterMark} || $state->{ended} )) {
        debug( 'read: emitReadable', $state->{length}, $state->{ended} );
        if ($state->{length} == 0 && $state->{ended} ){
            endReadable($this);
        } else {
            emitReadable($this);
        }
        return undef;
    }

    $n = howMuchToRead($n, $state);
    
    #if we've ended, and we're now clear, then finish it up.
    if ($n == 0 && $state->{ended} ) {
        endReadable($this) if $state->{length} == 0;
        return undef;
    }

    #All the actual chunk generation logic needs to be
    #*below* the call to _read.  The reason is that in certain
    #synthetic stream cases, such as passthrough streams, _read
    #may be a completely synchronous operation which may change
    #the state of the read buffer, providing enough data when
    #before there was *not* enough.

    #So, the steps are:
    #1. Figure out what the state of things will be after we do
    #a read from the buffer.

    #2. If that resulting state will trigger a _read, then call _read.
    #Note that this may be asynchronous, or synchronous.  Yes, it is
    #deeply ugly to write APIs this way, but that still doesn't mean
    #that the Readable class should behave improperly, as streams are
    #designed to be sync/async agnostic.
    #Take note if the _read call is sync or async (ie, if the read call
    #has returned yet), so that we know whether or not it's safe to emit
    #'readable' etc.

    #3. Actually pull the requested chunks out of the buffer and return.
  
    #if we need a readable event, then we need to do some reading.
    my $doRead = $state->{needReadable};
    debug('need readable', $doRead);

    #if we currently have less than the highWaterMark, then also read some
    if ($state->{length} == 0 || $state->{length} - $n < $state->{highWaterMark} ) {
        $doRead = 1;
        debug('length less than watermark', $doRead);
    }

    #however, if we've ended, then there's no point, and if we're already
    #reading, then it's unnecessary.
    if ( $state->{ended} || $state->{reading} ) {
        $doRead = 0;
        debug('reading or ended', $doRead);
    }

    if ($doRead) {
        debug('do read');
        $state->{reading} = 1;
        $state->{sync} = 1;
        #if the length is currently zero, then we *need* a readable event.
        $state->{needReadable} = 1 if $state->{length} == 0;
        #call internal read method
        $this->_read( $state->{highWaterMark} );
        $state->{sync} = 0;
    }

    #If _read pushed data synchronously, then `reading` will be false,
    #and we need to re-evaluate how much data we can return to the user.
    if ( $doRead && !$state->{reading} ){
        $n = howMuchToRead($nOrig, $state);
    }
    
    my $ret;
    if ($n > 0) {
        $ret = fromList($n, $state);
    } else {
        $ret = undef;
    }
  
    if ($util->isNull($ret)) {
        $state->{needReadable} = 1;
        $n = 0;
    }

    $state->{length} -= $n;

    #If we have nothing in the buffer, then we want to know
    #as soon as we *do* get something into the buffer.
    if ($state->{length} == 0 && !$state->{ended}) {
        $state->{needReadable} = 1;
    }
    
    #If we tried to read() past the EOF, then emit end on the next tick.
    if ($nOrig && $nOrig != $n && $state->{ended} && $state->{length} == 0){
        endReadable($this);
    }
    
    $this->emit('data', $ret) if !$util->isNull($ret);
    return $ret;
}

sub howMuchToRead {
    my ($n, $state) = @_;
    
    return 0 if $state->{length} == 0 && $state->{ended};
    
    if ( $state->{objectMode} ) {
        return defined $n && $n == 0 ? 0 : 1;
    }

    #if (isNaN(n) || util.isNull(n)) {
    if (!defined $n) {
        
        #only flow one buffer at a time
        if ($state->{flowing} && scalar @{ $state->{buffer} } ) {
            return _getObjLength($state->{buffer}->[0]);
        } else {
            return $state->{length};
        }
    }

    return 0 if $n <= 0;

    #If we're asking for more than the target buffer level,
    #then raise the water mark.  Bump up to the next highest
    #power of 2, to prevent increasing it excessively in tiny
    #amounts.
    if ($n > $state->{highWaterMark}){
        $state->{highWaterMark} = roundUpToNextPowerOf2($n);
    }
    #don't have that much.  return null, unless we've ended.
    if ($n > $state->{length}) {
        if ( !$state->{ended} ) {
            $state->{needReadable} = 1;
            return 0;
        } else {
            return $state->{length};
        }
    }
    
    return $n;
}

sub needMoreData {
    my ($state) = @_;
    return !$state->{ended} &&
        ($state->{needReadable} ||
        $state->{length} < $state->{highWaterMark} ||
        $state->{length} == 0);
}

sub push {
    my ($this, $chunk, $encoding) = @_;
    my $state = $this->{_readableState};
    
    ##- FIXME: do we really need to pass Rum::Buffer
    ##- or even do we really need Rum::Buffer at all
    ##- it's the source of all slowness
    ##- we can just pass a raw string
    if ( $util->isString($chunk) && !$state->{objectMode} ) {
        $encoding = $encoding || $state->{defaultEncoding};
        if ( !$state->{encoding} || $encoding ne $state->{encoding} ) {
            $chunk = Rum::Buffer->new($chunk, $encoding);
            $encoding = '';
        }
    }
    
    return readableAddChunk($this, $state, $chunk, $encoding, 0);
}

#Unshift should *always* be something directly out of read()
sub unshift {
    my ($this,$chunk) = @_;
    my $state = $this->{_readableState};
    return readableAddChunk($this, $state, $chunk, '', 1);
}

sub chunkInvalid {
    my ($state, $chunk) = @_;
    my $er;
    if (!$util->isBuffer($chunk) &&
      !$util->isString($chunk) &&
      !$util->isNullOrUndefined($chunk) &&
      !$state->{objectMode} &&
      !$er) {
        $er = Rum::Error->new('Invalid non-string/buffer chunk');
    }
    return $er;
}

sub onEofChunk {
    my ($stream, $state) = @_;
    if ( $state->{decoder} && !$state->{ended} ) {
        my $chunk = $state->{decoder}->end();
        if ($chunk && $chunk->length) {
            CORE::push @{$state->{buffer}} ,$chunk;
            $state->{length} += $state->{objectMode} ? 1 : $chunk->length;
        }
    }
    
    $state->{ended} = 1;
    #emit 'readable' now to make sure it gets picked up.
    emitReadable($stream);
}

#Don't emit readable right away in sync mode, because this can trigger
#another read() call => stack overflow.  This way, it might trigger
#a nextTick recursion warning, but that's not so bad.
sub emitReadable {
    my ($stream) = @_;
    my $state = $stream->{_readableState};
    $state->{needReadable} = 0;
    if (!$state->{emittedReadable}) {
    debug('emitReadable', $state->{flowing});
    $state->{emittedReadable} = 1;
        if ($state->{sync}) {
            process->nextTick( sub {
                emitReadable_($stream);
            });
        }
        else {
            emitReadable_($stream);
        }
    }
}

sub emitReadable_ {
    my ($stream) = @_;
    debug('emit readable');
    $stream->emit('readable');
    flow($stream);
}

sub flow {
    my ($stream) = @_;
    my $state = $stream->{_readableState};
    debug('flow', $state->{flowing});
    if ( $state->{flowing} ) {
        my $chunk;
        do {
            $chunk = $stream->read();
        } while ( defined $chunk && $state->{flowing} );
    }
}

#set up data events if they are asked for
#Ensure readable listeners eventually get something
sub on {
    my ($this, $ev, $fn) = @_;
    my $res = Rum::Stream::on($this, $ev, $fn);
    #If listening to data, and it has not explicitly been paused,
    #then call resume to start the flow of data on the next tick.
    if ($ev eq 'data' && !defined $this->{_readableState}->{flowing} ) {
        $this->resume();
    }
    
    if ( $ev eq 'readable' && $this->{readable} ) {
        my $state = $this->{_readableState};
        if ( !$state->{readableListening} ) {
            $state->{readableListening} = 1;
            $state->{emittedReadable} = 0;
            $state->{needReadable} = 1;
            if ( !$state->{reading} ) {
                my $self = $this;
                process->nextTick( sub {
                    debug('readable nexttick read 0');
                    $self->read(0);
                });
            } elsif ($state->{length} ) {
                emitReadable($this, $state);
            }
        }
    }
    return $res;
}

sub addListener { &on }

#pause() and resume() are remnants of the legacy readable stream API
#If the user uses them, then switch into old mode.
sub resume {
    my $this = shift;
    my $state = $this->{_readableState};
    if (!$state->{flowing}) {
        debug('resume');
        $state->{flowing} = 1;
        if (!$state->{reading}) {
            debug('resume read 0');
            $this->read(0);
        }
        _resume($this, $state);
    }
    return $this;
}

sub _resume {
    my ($stream, $state) = @_;
    if ( !$state->{resumeScheduled} ) {
        $state->{resumeScheduled} = 1;
        process->nextTick( sub {
            resume_($stream, $state);
        });
    }
}

sub resume_ {
    my ($stream, $state) = @_;
    $state->{resumeScheduled} = 0;
    $stream->emit('resume');
    flow($stream);
    if ($state->{flowing} && !$state->{reading}) {
        $stream->read(0);
    }
}

sub pause {
    my $this = shift;
    debug('call pause flowing=%j', $this->{_readableState}->{flowing});
    if ($this->{_readableState}->{flowing} ) {
        debug('pause');
        $this->{_readableState}->{flowing} = 0;
        $this->emit('pause');
    }
    
    return $this;
}

sub maybeReadMore {
    my ($stream, $state) = @_;
    if ( !$state->{readingMore} ) {
        $state->{readingMore} = 1;
        process->nextTick( sub {
            maybeReadMore_($stream, $state);
        });
    }
}

sub maybeReadMore_ {
    my ($stream, $state) = @_;
    my $len = $state->{length};
    
    while (!$state->{reading} && !$state->{flowing} && !$state->{ended} &&
        $state->{length} < $state->{highWaterMark} ) {
        debug('maybeReadMore read 0');
        $stream->read(0);
        if ($len == $state->{length}) {
            #didn't get any data, stop spinning.
            last;
        } else {
            $len = $state->{length};
        }
    }
    $state->{readingMore} = 0;
}

sub _read  {
    my ($this,$n) = @_;
    if ($this->{_read} && ref $this->{_read} eq 'CODE') {
        return $this->{_read}->($n);
    }
    $this->emit('error', Rum::Error->new('not implemented'));
}

#Pluck off n bytes from an array of buffers.
#Length is the combined lengths of all the buffers in the list.
sub fromList {
    my ($n, $state) = @_;
    my $list = $state->{buffer};
    my $length = $state->{length};
    my $stringMode = !!$state->{decoder};
    my $objectMode = !!$state->{objectMode};
    my $ret;
    #nothing in the list, definitely empty.
    return undef if (scalar @{$list} == 0);

    if ($length == 0) {
        $ret = undef;
    } elsif ($objectMode) {
        $ret = shift @{$list};
    } elsif (!$n || $n >= $length) {
        #read it all, truncate the array.
        if ($stringMode) {
            $ret = join '', @{$list};
        } else {
            $ret = Rum::Buffer->concat($list, $length);
        }
        $state->{buffer} = [];
    } else {
        #read just some of it.
        if ($n < _getObjLength($list->[0]) ) {
            #just take a part of the first list item.
            #slice is the same for buffers and strings.
            my $buf = $list->[0];
            $ret = $buf->slice(0, $n);
            $list->[0] = $buf->slice($n);
        } elsif ( $n == _getObjLength($list->[0]) ) {
            #first list is a perfect match
            $ret = shift @{$list};
        } else {
            #complex case.
            #we have enough to cover it, but it spans past the first buffer.
            if ($stringMode){
                $ret = '';
            } else {
                $ret = Rum::Buffer->new($n);
            }
            
            my $c = 0;
            for (my $i = 0, my $l = scalar @{$list}; $i < $l && $c < $n; $i++) {
                my $buf = $list->[0];
                my $cpy = min($n - $c, $buf->length);
                
                if ($stringMode) {
                    $ret .= $buf->slice(0, $cpy);
                } else {
                    $buf->copy($ret, $c, 0, $cpy);
                }
                
                if ($cpy < $buf->length) {
                    $list->[0] = $buf->slice($cpy);
                } else {
                    shift @{$list};
                }
                $c += $cpy;
            }
        }
    }
    return $ret;
}

sub endReadable {
    my ($stream) = @_;
    my $state = $stream->{_readableState};

    #If we get here before consuming all the bytes, then that is a
    #bug.  Should never happen.
    if ($state->{length} > 0) {
        Carp::croak('endReadable called on non-empty stream');
    }
    
    if (!$state->{endEmitted}) {
        $state->{ended} = 1;
        process->nextTick( sub {
            #Check that we didn't get one last unshift.
            if (!$state->{endEmitted} && $state->{length} == 0) {
                $state->{endEmitted} = 1;
                $stream->{readable} = 0;
                $stream->emit('end');
            }
        });
    }
}


###pipe
sub pipe {
    my ($this, $dest, $pipeOpts) = @_;
    my $src = $this;
    my $state = $this->{_readableState};
    
    if ($state->{pipesCount} == 0) {
        $state->{pipes} = $dest;
    } elsif ($state->{pipesCount} == 1) {
        $state->{pipes} = [$state->{pipes}, $dest];
    } else {
        CORE::push @{$state->{pipes}}, $dest;
    }
    
    my ($onclose,$onfinish,$onpipe,$onend,$cleanup,$ondata,$onerror,$unpipe,$onunpipe);
    
    $state->{pipesCount} += 1;
    
    debug('pipe count=%d opts=%j', $state->{pipesCount}, $pipeOpts);
    
    my $doEnd = (!$pipeOpts || $pipeOpts->{end}) &&
              $dest != process->stdout &&
              $dest != process->stderr;
    
    
    $onend = sub {
        debug('onend');
        $dest->end();
    };
    
    #when the dest drains, it reduces the awaitDrain counter
    #on the source.  This would be more elegant with a .once()
    #handler in flow(), but adding and removing repeatedly is
    #too slow.
    my $ondrain = pipeOnDrain($src);
    
    $dest->on('drain', $ondrain);
    
    $cleanup = sub {
        debug('cleanup');
        #cleanup event handlers once the pipe is broken
        $dest->removeListener('close', $onclose);
        $dest->removeListener('finish', $onfinish);
        $dest->removeListener('drain', $ondrain);
        $dest->removeListener('error', $onerror);
        $dest->removeListener('unpipe', $onunpipe);
        $src->removeListener('end', $onend);
        $src->removeListener('end', $cleanup);
        $src->removeListener('data', $ondata);
        
        #if the reader is waiting for a drain event from this
        #specific writer, then it would cause it to never start
        #flowing again.
        #So, if this is awaiting a drain, then we just call it now.
        #If we don't know, then assume that we are waiting for one.
        if ($state->{awaitDrain} &&
        (!$dest->{_writableState} || $dest->{_writableState}->{needDrain} )){
            $ondrain->();
        }
    };
    
    my $endFn = $doEnd ? $onend : $cleanup;
    if ($state->{endEmitted}) {
        process->nextTick($endFn);
    } else {
        $src->once('end', $endFn);
    }
    
    $onunpipe = sub {
        my ($this,$readable) = @_;
        debug('onunpipe');
        if ($readable == $src) {
            $cleanup->();
        }
    };
    
    $dest->on('unpipe', $onunpipe);
    
    $ondata = sub {
        my ($this,$chunk) = @_;
        debug('ondata');
        
        my $ret = $dest->write($chunk);
        if (!$ret) {
            debug('false write response, pause',
            $src->{_readableState}->{awaitDrain});
            $src->{_readableState}->{awaitDrain}++;
            $src->pause();
        }
    };
    $src->on('data', $ondata);
    
    #if the dest has an error, then stop piping into it.
    #however, don't suppress the throwing behavior for this.
    $onerror = sub {
        my ($this,$er) = @_;
        debug('onerror', $er);
        $unpipe->();
        $dest->removeListener('error', $onerror);
        if ($this->listenerCount($dest, 'error') == 0){
            $dest->emit('error', $er);
        }
    };
    
    #This is a brutally ugly hack to make sure that our error handler
    #is attached before any userland ones.  NEVER DO THIS.
    if (!$dest->{_events} || !$dest->{_events}->{error} ){
        $dest->on('error', $onerror);
    } elsif (ref $dest->{_events}->{error} eq 'ARRAY'){
        CORE::unshift @{$dest->{_events}->{error}}, $onerror;
    } else {
        $dest->{_events}->{error} = [$onerror, $dest->{_events}->{error}];
    }
    
    #Both close and finish should trigger unpipe, but only once.
    $onclose = sub {
        $dest->removeListener('finish', $onfinish);
        $unpipe->();
    };
  
    $dest->once('close', $onclose);
    $onfinish = sub {
        debug('onfinish');
        $dest->removeListener('close', $onclose);
        $unpipe->();
    };
    
    $dest->once('finish', $onfinish);
    
    $unpipe = sub {
        debug('unpipe');
        $src->unpipe($dest);
    };
    
    #tell the dest that it's being piped to
    $dest->emit('pipe', $src);

    #start the flow if it hasn't been started already.
    if (!$state->{flowing}) {
        debug('pipe resume');
        $src->resume();
    }
    
    return $dest;
}

sub pipeOnDrain {
    my ($src) = @_;
    return sub {
        my $state = $src->{_readableState};
        debug('pipeOnDrain', $state->{awaitDrain});
        if ($state->{awaitDrain}){
            $state->{awaitDrain}--;
        }
        if ($state->{awaitDrain} == 0 && $src->listenerCount($src, 'data')) {
            $state->{flowing} = 1;
            flow($src);
        }
    };
}

sub unpipe {
    my ($this,$dest) = @_;
    my $state = $this->{_readableState};

    #if we're not piping anywhere, then do nothing.
    return $this if ($state->{pipesCount} == 0);

    #just one destination.  most common case.
    if ($state->{pipesCount} == 1) {
        #passed in one, but it's not the right one.
        return $this if ($dest && $dest != $state->{pipes});
        
        $dest = $state->{pipes} if (!$dest);
        
        #got a match.
        $state->{pipes} = undef;
        $state->{pipesCount} = 0;
        $state->{flowing} = undef;
        
        $dest->emit('unpipe', $this) if $dest;
        
        return $this;
    }
    
    #slow case. multiple pipe destinations.
    my $len = $state->{pipesCount};
    my $pipes = $state->{pipes};
    
    if (!$dest) {
        #remove all.
        my $dests = $state->{pipes};
        
        $state->{pipes} = undef;
        $state->{pipesCount} = 0;
        $state->{flowing} = 0;
        
        foreach my $dd (@{$dests}) {
            $dd->emit('unpipe', $this);
        }
        
        return $this;
    }

    #try to find the right one.
    #var i = state.pipes.indexOf($dest);
    my $i;
    for ( 0 .. ($len - 1) ){
        $i = $_ if $pipes->[$_] == $dest;
    }
    return $this if !defined $i;
    
    splice @{$state->{pipes}}, $i, 1;
    $state->{pipesCount} -= 1;
  
    if ($state->{pipesCount} == 1) {
        $state->{pipes} = $state->{pipes}->[0];
    }

    $dest->emit('unpipe', $this);
    return $this;
}

##get length of either buffer or string
sub _getLength {
    return !ref $_[0] ? length $_[0] : $_[0]->length;
}

sub _getObjLength {
    return length $_[0];
}

#backwards compatibility.
my $StringDecoder;
sub setEncoding {
    my $this = shift;
    my $enc = shift;
    if (!$StringDecoder){
        require Rum::StringDecoder;
        $StringDecoder = 'Rum::StringDecoder';
    }
    
    $this->{_readableState}->{decoder} = $StringDecoder->new($enc);
    $this->{_readableState}->{encoding} = $enc;
    return $this;
}

package Rum::Stream::Readable::State; {
    use strict;
    use warnings;
    use Rum::StringDecoder;
    my $StringDecoder = 'Rum::StringDecoder';
    sub new {
        my ($class, $options, $stream) = @_;
        $options = $options || {};
        
        my $this = bless {},$class;
        
        #the point at which it stops calling _read() to fill the buffer
        #Note: 0 is a valid value, means "don't call _read preemptively ever"
        my $hwm = $options->{highWaterMark};
        my $defaultHwm = $options->{objectMode} ? 16 : 16 * 1024;
        $this->{highWaterMark} = !defined $hwm ?  $defaultHwm : $hwm;
        #cast to ints.
        $this->{highWaterMark} = ~~$this->{highWaterMark};
        $this->{buffer} = [];
        $this->{length} = 0;
        $this->{pipes} = undef;
        $this->{pipesCount} = 0;
        $this->{flowing} = undef;
        $this->{ended} = 0;
        $this->{endEmitted} = 0;
        $this->{reading} = 0;
        #a flag to be able to tell if the onwrite cb is called immediately,
        #or on a later tick.  We set this to true at first, because any
        #actions that shouldn't happen until "later" should generally also
        #not happen before the first write call.
        $this->{sync} = 1;
        
        #whenever we return null, then we set a flag to say
        #that we're awaiting a 'readable' event emission.
        $this->{needReadable} = 0;
        $this->{emittedReadable} = 0;
        $this->{readableListening} = 0;
      
      
        #object stream flag. Used to make read(n) ignore n and to
        #make all the buffer merging and length checks go away
        $this->{objectMode} = !!$options->{objectMode};
      
        #Crypto is kind of old and crusty.  Historically, its default string
        #encoding is 'binary' so we have to make this configurable.
        #Everything else in the universe uses 'utf8', though.
        $this->{defaultEncoding} = $options->{defaultEncoding} || 'utf8';
      
        #when piping, we only care about 'readable' events that happen
        #after read()ing all the bytes and not getting any pushback.
        $this->{ranOut} = 0;
      
        #the number of writers that are awaiting a drain event in .pipe()s
        $this->{awaitDrain} = 0;
      
        #if true, a maybeReadMore has been scheduled
        $this->{readingMore} = 0;
      
        $this->{decoder} = undef;
        $this->{encoding} = undef;
        if ( $options->{encoding} ) {
            $this->{decoder} = $StringDecoder->new($options->{encoding});
            $this->{encoding} = $options->{encoding};
        }
        return $this;
    }
}

1;

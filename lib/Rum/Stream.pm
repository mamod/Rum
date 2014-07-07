package Rum::Stream;
use lib '../';

use warnings;
use strict;
require Rum::Stream::Writable;
require Rum::Stream::Duplex;
use base 'Rum::Events';

sub Readable { 'Rum::Stream::Readable' }
sub Writable { 'Rum::Stream::Writable' }
sub Duplex   { 'Rum::Stream::Duplex'   }

sub new {
    bless {}, __PACKAGE__;
}

sub on { Rum::Events::on(@_) }

sub pipe {
    my ($source, $dest, $options) = @_;
    my $ondata = sub {
        my ($this,$chunk) = @_;
        if ($dest->{writable}) {
            if (!$dest->write($chunk) && $source->{pause}) {
                $source->pause();
            }
        }
    };
    
    $source->on('data', $ondata);
    
    my $ondrain = sub {
        if ($source->{readable} && $source->{resume}) {
            $source->resume();
        }
    };
    
    $dest->on('drain', $ondrain);
    
    my $didOnEnd = 0;
    my $onend = sub {
        return if $didOnEnd;
        $didOnEnd = 1;
        $dest->end();
    };
    
    my $onclose = sub {
        return if $didOnEnd;
        $didOnEnd = 1;
        $dest->destroy() if ($dest->can('destroy'));
    };
    
    #If the 'end' option is not supplied, dest.end() will be called when
    #source gets the 'end' or 'close' events.  Only dest.end() once.
    if (!$dest->{_isStdio} && (!$options || $options->{end} )) {
        $source->on('end', $onend);
        $source->on('close', $onclose);
    }
    
    my $cleanup;
    #don't leave dangling pipes when there are errors.
    my $onerror = sub {
        my ($this,$er) = @_;
        $cleanup->();
        if ($this->listenerCount($this, 'error') == 0) {
            $er->throw(); #Unhandled stream error in pipe.
        }
    };
    
    #remove all the event listeners that were added.
    $cleanup = sub {
        $source->removeListener('data', $ondata);
        $dest->removeListener('drain', $ondrain);
        $source->removeListener('end', $onend);
        $source->removeListener('close', $onclose);
        $source->removeListener('error', $onerror);
        $dest->removeListener('error', $onerror);
        $source->removeListener('end', $cleanup);
        $source->removeListener('close', $cleanup);
        $dest->removeListener('close', $cleanup);
    };
    
    $source->on('error', $onerror);
    $dest->on('error', $onerror);
    
    $source->on('end', $cleanup);
    $source->on('close', $cleanup);
    
    $dest->on('close', $cleanup);
    $dest->emit('pipe', $source);
    
    #Allow for unix-like usage: A.pipe(B).pipe(C)
    return $dest;
}

1;

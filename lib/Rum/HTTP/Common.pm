package Rum::HTTP::Common;
use strict;
use warnings;
use Data::Dumper;
use List::Util 'min';
use Rum::HTTP::Parser;
use Rum::HTTP::Incoming;
use Rum::FreeList;
use Rum;

my $util = 'Rum::Utils';
my $FreeList = 'Rum::FreeList';
our $chunkExpression = qr/chunk/i;
our $continueExpression = qr/100-continue/i;
our $CRLF = "\r\n";

*readStart = \&Rum::HTTP::Incoming::readStart;
*readStop = \&Rum::HTTP::Incoming::readStop;

*debug = $util->debuglog('http');

sub parserOnHeadersComplete {
    
    my ($this, $info) = @_;
    debug('parserOnHeadersComplete', $info);
    my $parser = $this;
    my $headers = $info->{headers};
    my $url = $info->{url};
    
    if (!$headers) {
        $headers = $parser->{_headers};
        $parser->{_headers} = [];
    }
    
    if (!$url) {
        $url = $parser->{_url};
        $parser->{_url} = '';
    }
    
    $parser->{incoming} = Rum::HTTP::Incoming->new($parser->{socket});
    $parser->{incoming}->{httpVersionMajor} = $info->{versionMajor};
    $parser->{incoming}->{httpVersionMinor} = $info->{versionMinor};
    $parser->{incoming}->{httpVersion} = $info->{versionMajor} . '.' . $info->{versionMinor};
    $parser->{incoming}->{url} = $url;
    
    my $n = scalar @{$headers};
    
    #If parser.maxHeaderPairs <= 0 - assume that there're no limit
    if ($parser->{maxHeaderPairs} > 0) {
        $n = min($n, $parser->{maxHeaderPairs});
    }
    
    $parser->{incoming}->_addHeaderLines($headers, $n);
    
    if ($util->isNumber($info->{method})) {
        #server only
        $parser->{incoming}->{method} = $Rum::HTTP::Parser::Methods[$info->{method}];
    } else {
        #client only
        $parser->{incoming}->{statusCode} = $info->{statusCode};
        $parser->{incoming}->{statusMessage} = $info->{statusMessage};
    }
    
    $parser->{incoming}->{upgrade} = $info->{upgrade};
    
    my $skipBody = 0; # response to HEAD or CONNECT
    
    if (!$info->{upgrade}) {
        #For upgraded connections and CONNECT method request,
        #we'll emit this after parser.execute
        #so that we can capture the first part of the new protocol
        $skipBody = $parser->{onIncoming}->($this, $parser->{incoming}, $info->{shouldKeepAlive});
    }
    
    return $skipBody;
}

sub parserOnMessageComplete {
    my $this = shift;
    my $parser = $this;
    my $stream = $parser->{incoming};
    
    if ($stream) {
        $stream->{complete} = 1;
        #Emit any trailing headers.
        my $headers = $parser->{_headers};
        if (@{$headers}) {
            $parser->{incoming}->_addHeaderLines($headers, @{$headers});
            $parser->{_headers} = [];
            $parser->{_url} = '';
        }
        
        if (!$stream->{upgrade}) {
            #For upgraded connections, also emit this after parser.execute
            $stream->push(undef);
        }
    }
    
    if ($stream && !@{$parser->{incoming}->{_pendings}}) {
        #For emit end event
        $stream->push(undef);
    }
    
    #force to read the next incoming message
    readStart($parser->{socket});
}

#XXX This is a mess.
#TODO: http.Parser should be a Writable emits request/response events.
sub parserOnBody {
    my ($this, $b, $start, $len) = @_;
    my $parser = $this;
    my $stream = $parser->{incoming};
    #if the stream has already been removed, then drop it.
    if (!$stream) {
        return;
    }
    
    my $socket = $stream->{socket};
    #pretend this was the result of a stream._read call.
    if ($len > 0 && !$stream->{_dumped}) {
        my $slice = $b->slice($start, $start + $len);
        my $ret = $stream->push($slice);
        if (!$ret) {
            readStop($socket);
        }
    }
    
    return 0;
}

our $parsers = Rum::FreeList->new('parsers', 1000, sub {
    my $parser = Rum::HTTP::Parser->new('REQUEST');
    
    $parser->{_headers} = [];
    $parser->{_url} = '';
    
    #Only called in the slow case where slow means
    #that the request headers were either fragmented
    #across multiple TCP packets or too large to be
    #processed in a single run. This method is also
    #called to process trailing HTTP headers.
    
    $parser->{OnHeaders} = \&parserOnHeaders;
    $parser->{OnHeadersComplete} = \&parserOnHeadersComplete;
    $parser->{OnBody} = \&parserOnBody;
    $parser->{OnMessageComplete} = \&parserOnMessageComplete;
    
    return $parser;
});

sub ondrain {
    my $this = shift;
    if ($this->{_httpMessage}) {
        $this->{_httpMessage}->emit('drain');
    }
}

sub httpSocketSetup {
    my $socket = shift;
    $socket->removeListener('drain', \&ondrain);
    $socket->on('drain', \&ondrain);
}

sub freeParser {
    my ($parser, $req) = @_;
    if ($parser) {
        $parser->{_headers} = [];
        $parser->{onIncoming} = undef;
        if ($parser->{socket}){
            $parser->{socket}->{parser} = undef;
        }
        $parser->{socket} = undef;
        $parser->{incoming} = undef;
        $parsers->free($parser);
        $parser = undef;
    }
    if ($req) {
        $req->{parser} = undef;
    }
}

1;

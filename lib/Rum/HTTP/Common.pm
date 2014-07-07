package Rum::HTTP::Common;
use strict;
use warnings;
use Data::Dumper;
use Rum::FreeList;
use Rum;

my $FreeList = 'Rum::FreeList';
#my $HTTPParser = Require('http_parser')->{HTTPParser};

my $incoming = Require('_http_incoming');

#var IncomingMessage = incoming.IncomingMessage;
#var readStart = incoming.readStart;
#var readStop = incoming.readStop;
#
#var isNumber = require('util').isNumber;
#var debug = require('util').debuglog('http');
#exports.debug = debug;
#
#exports.CRLF = '\r\n';
#exports.chunkExpression = /chunk/i;
#exports.continueExpression = /100-continue/i;
#exports.methods = HTTPParser.methods;
#
#var kOnHeaders = HTTPParser.kOnHeaders | 0;
#var kOnHeadersComplete = HTTPParser.kOnHeadersComplete | 0;
#var kOnBody = HTTPParser.kOnBody | 0;
#var kOnMessageComplete = HTTPParser.kOnMessageComplete | 0;

1;

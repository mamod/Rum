package Rum::HTTP;
use strict;
use warnings;

use Rum qw[exports Require];

use Rum::HTTP::Common;
use Rum::HTTP::Server;
use Rum::HTTP::Incoming;
use Rum::HTTP::Outgoing;
use Rum::HTTP::Agent;
use Rum::HTTP::Client;

my $server = 'Rum::HTTP::Server';
my $client = 'Rum::HTTP::Client';
my $Agent = exports->{Agent} = 'Rum::HTTP::Agent';
my $ClientRequest = exports->{ClientRequest} = 'Rum::HTTP::Client';
my $util = Require('util');
my $common = 'Rum::HTTP::Common';
exports->{IncomingMessage} = 'Rum::HTTP::Incoming';

##exports.METHODS = util._extend([], common.methods).sort();
#exports->{parsers} = \&Rum::HTTP::Common::parsers;

exports->{OutgoingMessage} = 'Rum::HTTP::Outgoing';
exports->{ServerResponse} = 'Rum::HTTP::Server::Response';
exports->{STATUS_CODES}   = \%Rum::HTTP::Server::STATUS_CODES;
exports->{globalAgent} = Rum::HTTP::Agent::globalAgent();

##exports._connectionListener = server._connectionListener;
my $Server = exports->{Server} = sub {
    my $requestListener = shift;
    return Rum::HTTP::Server->new($requestListener);
};

exports->{createServer} = sub {
    my $requestListener = shift;
    return Rum::HTTP::Server->new($requestListener);
};

exports->{request} = sub {
    my ($options, $cb) = @_;
    return $ClientRequest->new($options, $cb);
};

exports->{get} = sub {
    my $req = exports->{request}->(@_);
    $req->end();
    return $req;
};

1;

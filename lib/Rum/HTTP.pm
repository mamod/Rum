package Rum::HTTP;
use strict;
use warnings;
use Rum::HTTP::Server;
use Rum::HTTP::Incoming;
use Rum::HTTP::Outgoing;
use Rum::HTTP::Agent;

use Rum ('exports');

##var util = require('util');
##var EventEmitter = require('events').EventEmitter;


exports->{IncomingMessage} = 'Rum::HTTP::Incoming';

##var common = require('_http_common');
##exports.METHODS = util._extend([], common.methods).sort();
##exports.parsers = common.parsers;


exports->{OutgoingMessage} = 'Rum::HTTP::Outgoing';

#var server = require('_http_server');
#
exports->{ServerResponse} = 'Rum::HTTP::Server::Response';
exports->{STATUS_CODES}   = \%Rum::HTTP::Server::STATUS_CODES;

#var agent = require('_http_agent');
my $Agent = exports->{Agent} = 'Rum::HTTP::Agent';

exports->{globalAgent} = Rum::HTTP::Agent::globalAgent();

#var client = require('_http_client');
#var ClientRequest = exports.ClientRequest = client.ClientRequest;

##exports.request = function(options, cb) {
##  return new ClientRequest(options, cb);
##};
##
##exports.get = function(options, cb) {
##  var req = exports.request(options, cb);
##  req.end();
##  return req;
##};
##
##exports._connectionListener = server._connectionListener;
##var Server = exports.Server = server.Server;
##
##exports.createServer = function(requestListener) {
##  return new Server(requestListener);
##};

exports->{createServer} = sub {
    my $requestListener = shift;
    return Rum::HTTP::Server->new($requestListener);
};

1;

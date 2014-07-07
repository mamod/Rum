package Rum::HTTP::Server;
use strict;
use warnings;
use base 'Rum::Net::Server';

our %STATUS_CODES = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing', ## RFC 2518, obsoleted by RFC 4918
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status', ## RFC 4918
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Moved Temporarily',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect', ## RFC 7238
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Time-out',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Requested Range Not Satisfiable',
    417 => 'Expectation Failed',
    418 => 'I\'m a teapot', ## RFC 2324
    422 => 'Unprocessable Entity', ## RFC 4918
    423 => 'Locked', ## RFC 4918
    424 => 'Failed Dependency', ## RFC 4918
    425 => 'Unordered Collection', ## RFC 4918
    426 => 'Upgrade Required', ## RFC 2817
    428 => 'Precondition Required', ## RFC 6585
    429 => 'Too Many Requests', ## RFC 6585
    431 => 'Request Header Fields Too Large',## RFC 6585
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Time-out',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates', ## RFC 2295
    507 => 'Insufficient Storage', ## RFC 4918
    509 => 'Bandwidth Limit Exceeded',
    510 => 'Not Extended', ## RFC 2774
    511 => 'Network Authentication Required' ## RFC 6585
);



sub new {
    my ($class, $requestListener) = @_;
    my $this = bless({}, $class);
    Rum::Net::Server::new($this, { allowHalfOpen => 1 });
    
    if ($requestListener) {
        $this->addListener('request', $requestListener);
    }
    
    #Similar option to this. Too lazy to write my own docs.
    #http://www.squid-cache.org/Doc/config/half_closed_clients/
    #http://wiki.squid-cache.org/SquidFaq/InnerWorkings#What_is_a_half-closed_filedescriptor.3F
    $this->{httpAllowHalfOpen} = 0;
    
    $this->addListener('connection', \&connectionListener);
    
    $this->addListener('clientError', sub {
        my ($err, $conn) = @_;
        $conn->destroy($err);
    });
    
    $this->{timeout} = 2 * 60 * 1000;
    
    return $this;
}

#util.inherits(Server, net.Server);
#
#
#Server.prototype.setTimeout = function(msecs, callback) {
#  this.timeout = msecs;
#  if (callback)
#    this.on('timeout', callback);
#};
#
#
#exports.Server = Server;

1;

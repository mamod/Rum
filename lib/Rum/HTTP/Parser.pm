package Rum::HTTP::Parser;
use strict;
use warnings;
#require 'F:\shared\R4\test\old\old2.pl';
use Rum::HTTP::Parser::PP;
use Data::Dumper;
use Rum::Error;
use Rum::Utils;
my $util = 'Rum::Utils';
use Scalar::Util 'weaken';
our @Methods = (
    "DELETE",
    "GET",
    "HEAD",
    "POST",
    "PUT",
    "CONNECT",
    "OPTIONS",
    "TRACE",
    "COPY",
    "LOCK",
    "MKCOL",
    "MOVE",
    "PROPFIND",
    "PROPPATCH",
    "SEARCH",
    "UNLOCK",
    "REPORT",
    "MKACTIVITY",
    "CHECKOUT",
    "MERGE",
    "MSEARCH",
    "NOTIFY",
    "SUBSCRIBE",
    "UNSUBSCRIBE",
    "PATCH",
    "PURGE",
    "MKCALENDAR"
);

sub new {
    my $class = shift;
    my $type = shift;
    my $self = bless {
        parser => {}
    }, $class;
    
    my $parser_type = $type eq 'REQUEST' ? HTTP_REQUEST() : HTTP_RESPONSE();
    weaken($self->{parser}->{_obj} = $self);
    http_parser_init($self->{parser}, $parser_type);
    $self->{parser}->{cb} = {
        on_headers_complete => \&on_headers_complete,
        on_header_field => \&on_header_field,
        on_error => \&on_error,
        on_body => \&on_body,
        on_header_value => \&on_header_value,
        on_status => \&on_status,
        on_message_complete => \&on_message_complete
    };
    
    return $self;
}

sub CreateHeaders {
    my $header_fields = shift;
    my $header_values = shift;
    my $headers = [];
    my $i = 0;
    for (0 .. @{$header_fields} - 1){
        $headers->[$i] = $header_fields->[$_];
        $headers->[$i+1] = $header_values->[$_];
        $i += 2;
    }
    return $headers;
}

sub on_header_value {
    my $parser = shift;
    push @{$parser->{__headers}}, $parser->{value};
    return 0;
}

sub on_header_field {
    my $parser = shift;
    push @{$parser->{__headers}}, $parser->{value};
    return 0;
}

sub finish {
    
}

sub on_status {
    my ($parser, $start, $len) = @_;
    $parser->{status_message} = substr $parser->{buffer}, $start, $len;
    return 0;
}

sub on_body {
    my ($parser, $start,$len) = @_;
    
    my $obj = $parser->{_obj};
    my $cb = $obj->{OnBody};
    
    if (ref $cb ne 'CODE') {
        return 0;
    }
    my $current_buffer = $parser->{current_buffer};
    my $r = $cb->($obj, $current_buffer, $start, $len);
    
    if (!defined $r) {
        $parser->{got_exception_} = 1;
        return -1;
    }
    
    return 0;
}

sub on_headers_complete {
    my $parser = shift;
    my $obj = $parser->{_obj};
    my $cb = $obj->{OnHeadersComplete};
    if (ref $cb ne 'CODE'){
        return 0;
    }
    
    my $message_info = {};
    
    if ($parser->{have_flushed_}) {
      #Slow case, flush remaining headers.
      Flush();
    } else {
        #Fast case, pass headers and URL to JS land.
        $message_info->{headers} = $parser->{__headers};
        
        if ($parser->{type} == HTTP_REQUEST()) {
            $message_info->{url} =  $parser->{url};
        }
    }
    
    $parser->{__headers} = [];
    
    #METHOD
    if ($parser->{type} == HTTP_REQUEST()) {
        $message_info->{method} = $parser->{method};
    }
    
    #STATUS
    if ($parser->{type} == HTTP_RESPONSE()) {
        $message_info->{statusCode} = $parser->{status_code};
        $message_info->{statusMessage} = $parser->{status_message};
        undef $parser->{status_message};
    }

    #VERSION
    $message_info->{versionMajor} = $parser->{http_major};
    $message_info->{versionMinor} = $parser->{http_minor};

    $message_info->{shouldKeepAlive} = http_should_keep_alive($parser);
    
    $message_info->{upgrade} = $parser->{upgrade} ? 1 : 0;
    
    my $head_response = $cb->($obj, $message_info);

    if (!defined $head_response) {
        $parser->{got_exception_} = 1;
        return -1;
    }
    
    return $head_response ? 1 : 0;
}

sub on_message_complete {
    my $parser = shift;
    my $obj = $parser->{_obj};
    my $cb = $obj->{OnMessageComplete};
    
    if (ref $cb ne 'CODE') {
        return 0;
    }
    
    my $r = $cb->($obj, 0, undef);
    
    if (!defined $r) {
        $parser->{got_exception_} = 1;
        return -1;
    }
    
    return 0;
}

sub on_error {
    my $parser = shift;
    my $error = shift;
    #print Dumper $parser->{headers};
    #print Dumper "Parser Error: " . $error;
}

sub reinitialize {
    my $self = shift;
    my $type = shift;
    my $parser = $self->{parser};
    my $parser_type = $type eq 'REQUEST' ? HTTP_REQUEST() : HTTP_RESPONSE();
    http_parser_init($parser, $parser_type);
}

my $i = 0;
sub execute {
    my ($self, $data) = @_;
    my $parser = $self->{parser};
    $parser->{current_buffer} = $data;
    
    my $nread = http_parser_execute($parser, $data->toString('raw'), $data->length);
    undef $parser->{current_buffer};
    if (!$parser->{upgrade} && $nread != $data->length){
        return Rum::Error->new($parser->{http_errmsg});
    }
    return $nread;
}

1;

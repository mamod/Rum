package Rum::HTTP::Parser::PP;
use strict;
use warnings;
use Data::Dumper;
use Carp;
use List::Util 'min';

use base qw/Exporter/;
our @EXPORT = qw (
    http_parser_init
    http_parser_execute
    http_should_keep_alive
    HTTP_REQUEST
    HTTP_RESPONSE
);

my ($HTTP_REQUEST, $HTTP_RESPONSE, $HTTP_BOTH ) = (0,1,2);

sub HTTP_RESPONSE {$HTTP_RESPONSE}
sub HTTP_REQUEST {$HTTP_REQUEST}

my $HTTP_PARSER_STRICT = 0;

my $HTTP_MAX_HEADER_SIZE = 1000;
my $ULLONG_MAX = 999 * 999 * 999;

my $PROXY_CONNECTION = "proxy-connection";
my $CONNECTION  = "connection";
my $CONTENT_LENGTH = "content-length";
my $TRANSFER_ENCODING = "transfer-encoding";
my $UPGRADE  = "upgrade";
my $CHUNKED = "chunked";
my $KEEP_ALIVE = "keep-alive";
my $CLOSE = "close";

my @CONNECTION = split '', $CONNECTION;
my @PROXY_CONNECTION = split '', $PROXY_CONNECTION;
my @CONTENT_LENGTH = split '', $CONTENT_LENGTH;
my @TRANSFER_ENCODING = split '', $TRANSFER_ENCODING;
my @UPGRADE = split '', $UPGRADE;
my @CHUNKED = split '', $CHUNKED;
my @KEEP_ALIVE = split '', $KEEP_ALIVE;
my @CLOSE = split '', $CLOSE;

my $CR = "\r";
my $LF = "\n";

##flags
my  $F_CHUNKED = 1 << 0;
my $F_CONNECTION_KEEP_ALIVE = 1 << 1;
my $F_CONNECTION_CLOSE = 1 << 2;
my $F_TRAILING = 1 << 3;
my $F_UPGRADE = 1 << 4;
my $F_SKIPBODY = 1 << 5;

my @tokens = (
#/* 0 nul 1 soh 2 stx 3 etx 4 eot 5 enq 6 ack 7 bel */
        0, 0, 0, 0, 0, 0, 0, 0,
#/* 8 bs 9 ht 10 nl 11 vt 12 np 13 cr 14 so 15 si */
        0, 0, 0, 0, 0, 0, 0, 0,
#/* 16 dle 17 dc1 18 dc2 19 dc3 20 dc4 21 nak 22 syn 23 etb */
        0, 0, 0, 0, 0, 0, 0, 0,
#/* 24 can 25 em 26 sub 27 esc 28 fs 29 gs 30 rs 31 us */
        0, 0, 0, 0, 0, 0, 0, 0,
#/* 32 sp 33 ! 34 " 35 # 36 $ 37 % 38 & 39 ' */
        0, '!', 0, '#', '$', '%', '&', '\'',
#/* 40 ( 41 ) 42 * 43 + 44 , 45 - 46 . 47 / */
        0, 0, '*', '+', 0, '-', '.', 0,
#/* 48 0 49 1 50 2 51 3 52 4 53 5 54 6 55 7 */
       '0 but true', '1', '2', '3', '4', '5', '6', '7',
#/* 56 8 57 9 58 : 59 ; 60 < 61 = 62 > 63 ? */
       '8', '9', 0, 0, 0, 0, 0, 0,
#/* 64 @ 65 A 66 B 67 C 68 D 69 E 70 F 71 G */
        0, 'a', 'b', 'c', 'd', 'e', 'f', 'g',
#/* 72 H 73 I 74 J 75 K 76 L 77 M 78 N 79 O */
       'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
#/* 80 P 81 Q 82 R 83 S 84 T 85 U 86 V 87 W */
       'p', 'q', 'r', 's', 't', 'u', 'v', 'w',
#/* 88 X 89 Y 90 Z 91 [ 92 \ 93 ] 94 ^ 95 _ */
       'x', 'y', 'z', 0, 0, 0, '^', '_',
#/* 96 ` 97 a 98 b 99 c 100 d 101 e 102 f 103 g */
       '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g',
#/* 104 h 105 i 106 j 107 k 108 l 109 m 110 n 111 o */
       'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
#/* 112 p 113 q 114 r 115 s 116 t 117 u 118 v 119 w */
       'p', 'q', 'r', 's', 't', 'u', 'v', 'w',
#/* 120 x 121 y 122 z 123 { 124 | 125 } 126 ~ 127 del */
       'x', 'y', 'z', 0, '|', 0, '~', 0 );


my @unhex = (
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    ,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    ,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    , 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,-1,-1,-1,-1,-1,-1
    ,-1,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1
    ,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    ,-1,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1
    ,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
);

my (  $s_dead
    , $s_start_req_or_res
    , $s_res_or_resp_H
    , $s_start_res
    , $s_res_H
    , $s_res_HT
    , $s_res_HTT
    , $s_res_HTTP
    , $s_res_first_http_major
    , $s_res_http_major #10
    , $s_res_first_http_minor
    , $s_res_http_minor
    , $s_res_first_status_code
    , $s_res_status_code
    , $s_res_status_start
    , $s_res_status
    , $s_res_line_almost_done
    
    , $s_start_req
    
    , $s_req_method
    , $s_req_spaces_before_url #20
    , $s_req_schema
    , $s_req_schema_slash
    , $s_req_schema_slash_slash
    , $s_req_server_start
    , $s_req_server
    , $s_req_server_with_at
    , $s_req_path
    , $s_req_query_string_start
    , $s_req_query_string
    , $s_req_fragment_start #30
    , $s_req_fragment
    , $s_req_http_start
    , $s_req_http_H
    , $s_req_http_HT
    , $s_req_http_HTT
    , $s_req_http_HTTP
    , $s_req_first_http_major
    , $s_req_http_major
    , $s_req_first_http_minor
    , $s_req_http_minor
    , $s_req_line_almost_done
    
    , $s_header_field_start
    , $s_header_field
    , $s_header_value_discard_ws #44
    , $s_header_value_discard_ws_almost_done
    , $s_header_value_discard_lws
    , $s_header_value_start
    , $s_header_value
    , $s_header_value_lws
    
    , $s_header_almost_done
    
    , $s_chunk_size_start
    , $s_chunk_size
    , $s_chunk_parameters
    , $s_chunk_size_almost_done
    
    , $s_headers_almost_done
    , $s_headers_done ##56
    
    #Important: 's_headers_done' must be the last 'header' state. All
    #states beyond this must be 'body' states. It is used for overflow
    #checking. See the PARSING_HEADER() macro.
    
    , $s_chunk_data
    , $s_chunk_data_almost_done
    , $s_chunk_data_done
    , $s_body_identity
    , $s_body_identity_eof
    , $s_message_done
) = (1..62);


#header_states
my ( $h_general
    , $h_C
    , $h_CO
    , $h_CON

    , $h_matching_connection
    , $h_matching_proxy_connection
    , $h_matching_content_length
    , $h_matching_transfer_encoding
    , $h_matching_upgrade
    
    , $h_connection
    , $h_content_length
    , $h_transfer_encoding
    , $h_upgrade
    
    , $h_matching_transfer_encoding_chunked
    , $h_matching_connection_keep_alive
    , $h_matching_connection_close
    
    , $h_transfer_encoding_chunked
    , $h_connection_keep_alive
    , $h_connection_close
) = (0 .. 19);

my @errno = my (
    $HPE_OK,
    $HPE_CB_message_begin,
    $HPE_CB_url,
    $HPE_CB_header_field,
    $HPE_CB_header_value,
    $HPE_CB_headers_complete,
    $HPE_CB_body,
    $HPE_CB_message_complete,
    $HPE_CB_status,
    $HPE_INVALID_EOF_STATE,
    $HPE_HEADER_OVERFLOW,
    $HPE_CLOSED_CONNECTION,
    $HPE_INVALID_VERSION,
    $HPE_INVALID_STATUS,
    $HPE_INVALID_METHOD,
    $HPE_INVALID_URL,
    $HPE_INVALID_HOST,
    $HPE_INVALID_PORT,
    $HPE_INVALID_PATH,
    $HPE_INVALID_QUERY_STRING,
    $HPE_INVALID_FRAGMENT,
    $HPE_LF_EXPECTED,
    $HPE_INVALID_HEADER_TOKEN,
    $HPE_INVALID_CONTENT_LENGTH,
    $HPE_INVALID_CHUNK_SIZE,
    $HPE_INVALID_CONSTANT,
    $HPE_INVALID_INTERNAL_STATE,
    $HPE_STRICT,
    $HPE_PAUSED,
    $HPE_UNKNOWN
) = (0 .. 29);

my @errmsg = (
    "success",
    "the on_message_begin callback failed",
    "the on_url callback failed",
    "the on_header_field callback failed",
    "the on_header_value callback failed",
    "the on_headers_complete callback failed",
    "the on_body callback failed",
    "the on_message_complete callback failed",
    "the on_status callback failed",
    "stream ended at an unexpected time",
    "too many header bytes seen; overflow detected",
    "data received after completed connection: close message",
    "invalid HTTP version",
    "invalid HTTP status code",
    "invalid HTTP method",
    "invalid URL",
    "invalid host",
    "invalid port",
    "invalid path",
    "invalid query string",
    "invalid fragment",
    "LF character expected",
    "invalid character in header",
    "invalid character in content-length header",
    "invalid character in chunk size header",
    "invalid constant string",
    "encountered unexpected internal state",
    "strict mode assertion failed",
    "parser is paused",
    "an unknown error occurred"
);

my (
    $HTTP_DELETE,
    $HTTP_GET,
    $HTTP_HEAD,
    $HTTP_POST,
    $HTTP_PUT,
    $HTTP_CONNECT,
    $HTTP_OPTIONS,
    $HTTP_TRACE,
    $HTTP_COPY,
    $HTTP_LOCK,
    $HTTP_MKCOL,
    $HTTP_MOVE,
    $HTTP_PROPFIND,
    $HTTP_PROPPATCH,
    $HTTP_SEARCH,
    $HTTP_UNLOCK,
    $HTTP_REPORT,
    $HTTP_MKACTIVITY,
    $HTTP_CHECKOUT,
    $HTTP_MERGE,
    $HTTP_MSEARCH,
    $HTTP_NOTIFY,
    $HTTP_SUBSCRIBE,
    $HTTP_UNSUBSCRIBE,
    $HTTP_PATCH,
    $HTTP_PURGE,
    $HTTP_MKCALENDAR
) = (0 .. 26);

my @method_strings = (
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

my %HPE_CB_ = (
    message_begin => $HPE_CB_message_begin,
    url => $HPE_CB_url,
    header_field => $HPE_CB_header_field,
    header_value => $HPE_CB_header_value,
    headers_complete => $HPE_CB_headers_complete,
    body => $HPE_CB_body,
    message_complete => $HPE_CB_message_complete,
    status => $HPE_CB_status,
);

sub SET_ERRNO {
    my $error = shift;
    my $p = shift;
    $p->{http_errno} = $error;
    $p->{http_errmsg} = $errmsg[$error];
}

sub PARSING_HEADER {
    my $state = shift;
    return $state <= $s_headers_done
}

sub HTTP_PARSER_ERRNO {
    my $p = shift;
    return $p->{http_errno};
}

sub STRICT_CHECK {
    if ($HTTP_PARSER_STRICT) {
        my $cond = shift;
        my $parser = shift;
        if ($cond) {
            SET_ERRNO($HPE_STRICT, $parser);
            return 1;
        }
        return 0;
    }
    return 0;
}

sub IS_NUM {
    my $c = shift;
    my $ord = ord($c);
    return $ord > 47 && $ord < 58;
}

sub IS_ALPHA {
    my $c = ord(lc shift);
    return $c >= 97 && $c <= 122;
}

sub MARK {
    my $marker = shift;
    my $parser = shift;
    $parser->{$marker . '_mark'} = $parser->{p};
}

sub TOKEN {
    my $c = shift;
    if ($HTTP_PARSER_STRICT) {
        return $tokens[ord($c)];
    }
    return $c eq ' ' ? ' ' : $tokens[ord($c)];
}

sub IS_URL_CHAR {
    return 1;
}

sub IS_ALPHANUM {
    my $c = shift;
    return IS_ALPHA($c) || IS_NUM($c);
}

sub IS_MARK {
    my $c = shift;
    $c eq '-' || $c eq '_' || $c eq '.' ||
    $c eq '!' || $c eq '~' || $c eq '*' || $c eq '\'' || $c eq '(' ||
    $c eq ')';
}

sub IS_USERINFO_CHAR {
    my $c = shift;
    IS_ALPHANUM($c) || IS_MARK($c) || $c eq '%' || 
        $c eq ';' || $c eq ':' || $c eq '&' || $c eq '=' || $c eq '+' ||
        $c eq '$' || $c eq ','
}

sub start_state {
    shift->{type} == $HTTP_REQUEST ? $s_start_req : $s_start_res;
}

sub NEW_MESSAGE {
    my $p = shift;
    http_should_keep_alive($p) ? start_state($p) : $s_dead
}

sub assert {
    #croak if !$_[0];
}

sub sizeof {length($_[0])+1}

sub CALLBACK_DATA_ {
    my ($FOR, $parser, $LEN, $ER) = @_;
    assert(HTTP_PARSER_ERRNO($parser) == $HPE_OK);
    my $FORMARK = $FOR . '_mark';
    my $ONFOR = 'on_' . $FOR;
    my $settings = $parser->{cb};
    if (defined $parser->{$FORMARK}) {
        if ($settings->{$ONFOR}) {
            if ($settings->{$ONFOR}->($parser, $parser->{$FORMARK}, $LEN)) {
                SET_ERRNO($HPE_CB_{$FOR}, $parser);
            }
            #We either errored above or got paused; get out
            if (HTTP_PARSER_ERRNO($parser) != $HPE_OK) {
                return $ER;
            }
        }
        
        $parser->{$FORMARK} = undef;
    }
    
    return 0;
}

#Run the data callback FOR and consume the current byte
sub CALLBACK_DATA {
    my $FOR = shift;
    my $parser = shift;
    CALLBACK_DATA_($FOR, $parser,
                   $parser->{p} - $parser->{$FOR . '_mark'},
                   $parser->{p} + 1);
}

sub CALLBACK_DATA_NOADVANCE {
    my $FOR = shift;
    my $parser = shift;
    return if !defined $parser->{$FOR . '_mark'};
    CALLBACK_DATA_($FOR, $parser,
                   $parser->{p} - $parser->{$FOR . '_mark'},
                   $parser->{p} );
}

sub CALLBACK_NOTIFY_ {
    my ($FOR, $parser, $ER) = @_;
    assert(HTTP_PARSER_ERRNO($parser) == $HPE_OK);
    my $settings = $parser->{cb};
    my $FORMARK = $FOR . '_mark';
    my $ONFOR = 'on_' . $FOR;
    if ($settings->{$ONFOR}) {
        if ($settings->{$ONFOR}->($parser)) {
            SET_ERRNO($HPE_CB_{$FOR}, $parser);
        }
        #We either errored above or got paused; get out
        if (HTTP_PARSER_ERRNO($parser) != $HPE_OK) {
            return $ER;
        } 
    }
    
    return 0;
}

#Run the notify callback FOR and consume the current byte
sub CALLBACK_NOTIFY {
    my $FOR = shift;
    my $parser = shift;
    
    #reset everything
    if ($FOR eq 'message_begin') {
        $parser->{header_values} = [];
        $parser->{header_fields} = [];
        $parser->{header_count} = -1;
        $parser->{start_header_count} = 0;
        $parser->{header_name} = '';
        $parser->{url} = '';
        $parser->{headers} = {};
    } elsif ($FOR eq 'message_complete'){
        undef $parser->{buffer};
    }
    
    CALLBACK_NOTIFY_($FOR, $parser, $parser->{p} - $parser->{len} + 1);
}

#Our URL parser.
#This is designed to be shared by http_parser_execute() for URL validation,
#hence it has a state transition + byte-for-byte interface. In addition, it
#is meant to be embedded in http_parser_parse_url(), which does the dirty
#work of turning state transitions URL components for its API.
#
#This function should only be invoked with non-space characters. It is
#assumed that the caller cares about (and can detect) the transition between
#URL and non-URL states by looking for these.
sub parse_url_char {
    my ($s, $ch) = @_;
    my $FALLTHROUGH = 0;
    if ($ch eq ' ' || $ch eq "\r" || $ch eq "\n") {
        return $s_dead;
    }
    
    if ($HTTP_PARSER_STRICT){
        if ($ch eq "\t" || $ch eq "\f") {
            return $s_dead;
        }
    }
    
    if ($s == $s_req_spaces_before_url){
        
        #Proxied requests are followed by scheme of an absolute URI (alpha).
        #All methods except CONNECT are followed by '/' or '*'.
        
        if ($ch eq '/' || $ch eq '*') {
            return $s_req_path;
        }
        
        if (IS_ALPHA($ch)) {
            return $s_req_schema;
        }
        
        #break;
        
    } elsif ($s == $s_req_schema) {
        if (IS_ALPHA($ch)) {
            return $s;
        }
        
        if ($ch eq ':') {
            return $s_req_schema_slash;
        }
        
        #break;
        
    } elsif ($s == $s_req_schema_slash) {
        if ($ch eq '/') {
            return $s_req_schema_slash_slash;
        }
        
        #break;
        
    } elsif ($s == $s_req_schema_slash_slash){
        if ($ch eq '/') {
            return $s_req_server_start;
        }
        
        #break;
        
    } elsif ($s == $s_req_server_with_at) {
        if ($ch eq '@') {
            return $s_dead;
        }
        $FALLTHROUGH = 1;
        #FALLTHROUGH
    }
    
    if ($FALLTHROUGH || $s == $s_req_server_start ||
        $s == $s_req_server) {
        $FALLTHROUGH = 0;
        if ($ch eq '/') {
            return $s_req_path;
        }
        
        if ($ch eq '?') {
            return $s_req_query_string_start;
        }
        
        if ($ch eq '@') {
            return $s_req_server_with_at;
        }
        
        if (IS_USERINFO_CHAR($ch) || $ch eq '[' || $ch eq ']') {
            return $s_req_server;
        }
        
        #break;
        
    } elsif ($s == $s_req_path){
        if (IS_URL_CHAR($ch)) {
            return $s;
        }
        
        if ($ch eq '?') {
            return $s_req_query_string_start;
        } elsif ($ch eq '#'){
            return $s_req_fragment_start;
        }
        
        #break;
        
    } elsif ($s == $s_req_query_string_start ||
             $s == $s_req_query_string ) {
        
        if (IS_URL_CHAR($ch)) {
            return $s_req_query_string;
        }
        
        if($ch eq '?') {
            #allow extra '?' in query string
            return $s_req_query_string;
        } elsif ($ch eq '#') {
            return $s_req_fragment_start;
        }
        
        #break;
        
    } elsif ($s == $s_req_fragment_start){
        if (IS_URL_CHAR($ch)) {
            return $s_req_fragment;
        }
        
        if ($ch eq '?') {
            return $s_req_fragment;
        } elsif ($ch eq '#'){
            return $s;
        }
        
        #break;
        
    } elsif ($s == $s_req_fragment){
        if (IS_URL_CHAR($ch)) {
            return $s;
        }
        
        if ($ch eq '?' || $ch eq '#') {
            return $s;
        }
        
        #break;
    }
    
    #We should never fall out of the switch above unless there's an error
    return $s_dead;
}

#Does the parser need to see an EOF to find the end of the message?
sub http_message_needs_eof {
    my $parser = shift;
    if ($parser->{type} == $HTTP_REQUEST) {
        return 0;
    }
    
    #See RFC 2616 section 4.4
    if (int($parser->{status_code} / 100) == 1 || # 1xx e.g. Continue
         $parser->{status_code} == 204 || # No Content
         $parser->{status_code} == 304 || # Not Modified
         $parser->{flags} & $F_SKIPBODY) { # response to a HEAD request
        return 0;
    }
    
    if (($parser->{flags} & $F_CHUNKED) ||
         $parser->{content_length} != $ULLONG_MAX) {
        return 0;
    }
    
    return 1;
}

sub http_should_keep_alive {
    my $parser = shift;
    if ($parser->{http_major} > 0 && $parser->{http_minor} > 0) {
        # HTTP/1.1
        if ($parser->{flags} & $F_CONNECTION_CLOSE) {
            return 0;
        }
    } else {
        # HTTP/1.0 or earlier
        if (!($parser->{flags} & $F_CONNECTION_KEEP_ALIVE)) {
            return 0;
        }
    }
    
    return !http_message_needs_eof($parser);
}

my %states = (
    $s_dead => sub {
        my $parser = shift;
        my $ch = shift;
        #this state is used after a 'Connection: close' message
        #the parser will error out if it reads another message
        if ($ch eq $CR || $ch eq $LF) {
            goto BREAK;
        }
        
        SET_ERRNO($HPE_CLOSED_CONNECTION,$parser);
        goto error;
    },
    
    $s_start_req_or_res => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR || $ch eq $LF) {
            goto BREAK;
        }
        
        $parser->{flags} = 0;
        $parser->{content_length} = $ULLONG_MAX;
        
        if ($ch eq 'H') {
            $parser->{state} = $s_res_or_resp_H;
            CALLBACK_NOTIFY('message_begin', $parser) && goto error;
        } else {
            $parser->{type} = $HTTP_REQUEST;
            $parser->{state} = $s_start_req;
            goto reexecute_byte;
        }
        
        goto BREAK;
    },
    
    $s_res_or_resp_H => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq 'T') {
            $parser->{type} = $HTTP_RESPONSE;
            $parser->{state} = $s_res_HT;
        } else {
            if ($ch ne 'E') {
                SET_ERRNO($HPE_INVALID_CONSTANT,$parser);
                goto error;
            }
            
            $parser->{type} = $HTTP_REQUEST;
            $parser->{method} = $HTTP_HEAD;
            $parser->{index} = 2;
            $parser->{state} = $s_req_method;
        }
        
        goto BREAK;
    },
    
    $s_start_res => sub {
        my $parser = shift;
        my $ch = shift;
        $parser->{flags} = 0;
        $parser->{content_length} = $ULLONG_MAX;
        
        {
            my $switch = $ch;
            if ($switch eq 'H') {
                $parser->{state} = $s_res_H;
            } elsif ($switch eq $CR || $switch eq $LF){
                #nothing
            } else {
                SET_ERRNO($HPE_INVALID_CONSTANT,$parser);
                goto error;
            }
        }
        
        CALLBACK_NOTIFY('message_begin', $parser) && goto error;
        goto BREAK;
    },
    
    
    $s_res_H => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne 'T', $parser) && goto error;
        $parser->{state} = $s_res_HT;
        goto BREAK;
        
    },
    
    $s_res_HT => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne 'T', $parser) && goto error;
        $parser->{state} = $s_res_HTT;
        goto BREAK;
        
    },
    
    $s_res_HTT => sub {
        my $parser = shift;
        my $ch = shift;
        STRICT_CHECK($ch ne 'P', $parser) && goto error;
        $parser->{state} = $s_res_HTTP;
        goto BREAK;
    },
    
    $s_res_HTTP => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne '/', $parser) && goto error;
        $parser->{state} = $s_res_first_http_major;
        goto BREAK;
        
    },
    
    $s_res_first_http_major => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch < '0' || $ch > '9') {
            SET_ERRNO($HPE_INVALID_VERSION,$parser);
            goto error;
        }
        $parser->{http_major} = $ch;
        $parser->{state} = $s_res_http_major;
        goto BREAK;
    },
    
    #major HTTP version or dot
    $s_res_http_major => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq '.') {
            $parser->{state} = $s_res_first_http_minor;
            goto BREAK;
        }
        
        if (!IS_NUM($ch)) {
            SET_ERRNO($HPE_INVALID_VERSION,$parser);
            goto error;
        }
        
        $parser->{http_major} *= 10;
        $parser->{http_major} += $ch;
        
        if ($parser->{http_major} > 999) {
            SET_ERRNO($HPE_INVALID_VERSION,$parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    #first digit of minor HTTP version */
    $s_res_first_http_minor => sub {
        my $parser = shift;
        my $ch = shift;
        
        if (!IS_NUM($ch)) {
            SET_ERRNO($HPE_INVALID_VERSION,$parser);
            goto error;
        }
        
        $parser->{http_minor} = $ch;
        $parser->{state} = $s_res_http_minor;
        goto BREAK;
    },
    
    #minor HTTP version or end of request line
    $s_res_http_minor => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq ' ') {
            $parser->{state} = $s_res_first_status_code;
            goto BREAK;
        }
        
        if (!IS_NUM($ch)) {
            SET_ERRNO($HPE_INVALID_VERSION,$parser);
            goto error;
        }
        
        $parser->{http_minor} *= 10;
        $parser->{http_minor} += $ch;
        
        if ($parser->{http_minor} > 999) {
            SET_ERRNO($HPE_INVALID_VERSION,$parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    $s_res_first_status_code => sub {
        my $parser = shift;
        my $ch = shift;
        
        if (!IS_NUM($ch)) {
            if ($ch ne ' ') {
                goto BREAK;
            }
            
            SET_ERRNO($HPE_INVALID_STATUS,$parser);
            goto error;
        }
        
        $parser->{status_code} = $ch;
        $parser->{state} = $s_res_status_code;
        goto BREAK;
    },
    
    $s_res_status_code => sub {
        my $parser = shift;
        my $ch = shift;
        
        if (!IS_NUM($ch)) {
            if ($ch eq ' ') {
                $parser->{state} = $s_res_status_start;
            } elsif ($ch eq $CR){
                $parser->{state} = $s_res_line_almost_done;
            } elsif ($ch eq $LF){
                $parser->{state} = $s_header_field_start;
            } else {
                SET_ERRNO($HPE_INVALID_STATUS,$parser);
                goto error;
            }
            
            goto BREAK;
        }
        
        $parser->{status_code} *= 10;
        $parser->{status_code} += $ch;
        
        if ($parser->{status_code} > 999) {
            SET_ERRNO($HPE_INVALID_STATUS,$parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    $s_res_status_start => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR) {
            $parser->{state} = $s_res_line_almost_done;
            goto BREAK;
        }
        
        if ($ch eq $LF) {
            $parser->{state} = $s_header_field_start;
            goto BREAK;
        }
        
        MARK('status', $parser);
        $parser->{state} = $s_res_status;
        $parser->{index} = 0;
        goto BREAK;
    },
    
    $s_res_status => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR) {
            $parser->{state} = $s_res_line_almost_done;
            CALLBACK_DATA('status',$parser) && goto error;
            goto BREAK;
        }
        
        if ($ch eq $LF) {
            $parser->{state} = $s_header_field_start;
            CALLBACK_DATA('status',$parser) && goto error;
            goto BREAK;
        }
        
        goto BREAK;
    },
    
    $s_res_line_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        $parser->{state} = $s_header_field_start;
        goto BREAK;
    },
    
    $s_start_req => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR || $ch eq $LF) {
            goto BREAK;
        }
        
        $parser->{flags} = 0;
        $parser->{content_length} = $ULLONG_MAX;
        
        if (!IS_ALPHA($ch)) {
            SET_ERRNO($HPE_INVALID_METHOD, $parser);
            goto error;
        }
        
        $parser->{method} = 0;
        $parser->{index} = 1;
        
        {
            if    ($ch eq 'C') { $parser->{method} = $HTTP_CONNECT;}
            elsif ($ch eq 'D') { $parser->{method} = $HTTP_DELETE;}
            elsif ($ch eq 'G') { $parser->{method} = $HTTP_GET;}
            elsif ($ch eq 'H') { $parser->{method} = $HTTP_HEAD;}
            elsif ($ch eq 'L') { $parser->{method} = $HTTP_LOCK;}
            elsif ($ch eq 'M') { $parser->{method} = $HTTP_MKCOL;}
            elsif ($ch eq 'N') { $parser->{method} = $HTTP_NOTIFY;}
            elsif ($ch eq 'O') { $parser->{method} = $HTTP_OPTIONS;}
            elsif ($ch eq 'P') { $parser->{method} = $HTTP_POST;}
            elsif ($ch eq 'R') { $parser->{method} = $HTTP_REPORT;}
            elsif ($ch eq 'S') { $parser->{method} = $HTTP_SUBSCRIBE;}
            elsif ($ch eq 'T') { $parser->{method} = $HTTP_TRACE;}
            elsif ($ch eq 'U') { $parser->{method} = $HTTP_UNLOCK;}
            else {
                SET_ERRNO($HPE_INVALID_METHOD, $parser);
                goto error;
            }
        }
        
        $parser->{state} = $s_req_method;
        CALLBACK_NOTIFY('message_begin', $parser);
        goto BREAK;
    },
    
    $s_req_method => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq "\0") {
            SET_ERRNO($HPE_INVALID_METHOD, $parser);
            goto error;
        }
        
        my $matcher = $method_strings[$parser->{method}];
        ##XXX pre split things on compile time
        my @matcher = split '', $matcher;
        if ( $ch eq ' ' && !$matcher[$parser->{index}]) {
            $parser->{state} = $s_req_spaces_before_url;
        } elsif ($ch eq $matcher[$parser->{index}]) {
            # nada
        } elsif ($parser->{method} == $HTTP_CONNECT) {
            if ($parser->{index} == 1 && $ch eq 'H') {
                $parser->{method} = $HTTP_CHECKOUT;
            } elsif ($parser->{index} == 2 && $ch eq 'P') {
                $parser->{method} = $HTTP_COPY;
            } else {
                SET_ERRNO($HPE_INVALID_METHOD, $parser);
                goto error;
            }
        } elsif ($parser->{method} == $HTTP_MKCOL) {
            if ($parser->{index} == 1 && $ch eq 'O') {
                $parser->{method} = $HTTP_MOVE;
            } elsif ($parser->{index} == 1 && $ch eq 'E') {
                $parser->{method} = $HTTP_MERGE;
            } elsif ($parser->{index} == 1 && $ch eq '-') {
                $parser->{method} = $HTTP_MSEARCH;
            } elsif ($parser->{index} == 2 && $ch eq 'A') {
                $parser->{method} = $HTTP_MKACTIVITY;
            } elsif ($parser->{index} == 3 && $ch eq 'A') {
                $parser->{method} = $HTTP_MKCALENDAR;
            } else {
                SET_ERRNO($HPE_INVALID_METHOD, $parser);
                goto error;
            }
        } elsif ($parser->{method} == $HTTP_SUBSCRIBE) {
            if ($parser->{index} == 1 && $ch eq 'E') {
                $parser->{method} = $HTTP_SEARCH;
            } else {
                SET_ERRNO($HPE_INVALID_METHOD,$parser);
                goto error;
            }
        } elsif ($parser->{index} == 1 && $parser->{method} == $HTTP_POST) {
            if ($ch eq 'R') {
                $parser->{method} = $HTTP_PROPFIND; # or HTTP_PROPPATCH
            } elsif ($ch eq 'U') {
                $parser->{method} = $HTTP_PUT; # or HTTP_PURGE
            } elsif ($ch eq 'A') {
                $parser->{method} = $HTTP_PATCH;
            } else {
                SET_ERRNO($HPE_INVALID_METHOD, $parser);
                goto error;
            }
        } elsif ($parser->{index} == 2) {
            if ($parser->{method} == $HTTP_PUT) {
                if ($ch eq 'R') {
                    $parser->{method} = $HTTP_PURGE;
                } else {
                    SET_ERRNO($HPE_INVALID_METHOD, $parser);
                    goto error;
                }
            } elsif ($parser->{method} == $HTTP_UNLOCK) {
                if ($ch eq 'S') {
                    $parser->{method} = $HTTP_UNSUBSCRIBE;
                } else {
                    SET_ERRNO($HPE_INVALID_METHOD,$parser);
                    goto error;
                }
            } else {
                SET_ERRNO($HPE_INVALID_METHOD,$parser);
                goto error;
            }
        } elsif ($parser->{index} == 4 && $parser->{method} == $HTTP_PROPFIND && $ch eq 'P') {
            $parser->{method} = $HTTP_PROPPATCH;
        } else {
            SET_ERRNO($HPE_INVALID_METHOD, $parser);
            goto error;
        }
        
        ++$parser->{index};
        goto BREAK;
    },
    
    $s_req_spaces_before_url => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq ' ') { goto BREAK; }
        
        MARK('url',$parser);
        if ($parser->{method} == $HTTP_CONNECT) {
            $parser->{state} = $s_req_server_start;
        }
        
        $parser->{state} = parse_url_char($parser->{state}, $ch);
        if ($parser->{state} == $s_dead) {
            SET_ERRNO($HPE_INVALID_URL, $parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    ##multi 1;
    
    $s_req_http_start => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq 'H') {
            $parser->{state} = $s_req_http_H;
        } elsif ($ch eq ' ') {
            #nothing
        } else {
            SET_ERRNO($HPE_INVALID_CONSTANT, $parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    $s_req_http_H => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne 'T', $parser) && goto error;
        $parser->{state} = $s_req_http_HT;
        goto BREAK;
    },
    
    $s_req_http_HT => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne 'T', $parser) && goto error;
        $parser->{state} = $s_req_http_HTT;
        goto BREAK;
    },
    
    $s_req_http_HTT => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne 'P', $parser) && goto error;
        $parser->{state} = $s_req_http_HTTP;
        goto BREAK;
    },
    
    $s_req_http_HTTP => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne '/', $parser) && goto error;
        $parser->{state} = $s_req_first_http_major;
        goto BREAK;
    },
    
    #first digit of major HTTP version
    $s_req_first_http_major => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch < 1 || $ch > 9) {
            SET_ERRNO($HPE_INVALID_VERSION, $parser);
            goto error;
        }
        
        $parser->{http_major} = $ch;
        $parser->{state} = $s_req_http_major;
        goto BREAK;
    },
    
    #major HTTP version or dot
    $s_req_http_major => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq '.') {
            $parser->{state} = $s_req_first_http_minor;
            goto BREAK;
        }
        
        if (!IS_NUM($ch)) {
            SET_ERRNO($HPE_INVALID_VERSION, $parser);
            goto error;
        }
        
        $parser->{http_major} *= 10;
        $parser->{http_major} += $ch;
        
        if ($parser->{http_major} > 999) {
            SET_ERRNO($HPE_INVALID_VERSION, $parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    #first digit of minor HTTP version
    $s_req_first_http_minor => sub {
        my $parser = shift;
        my $ch = shift;
        
        if (!IS_NUM($ch)) {
            SET_ERRNO($HPE_INVALID_VERSION, $parser);
            goto error;
        }
        
        $parser->{http_minor} = $ch;
        $parser->{state} = $s_req_http_minor;
        goto BREAK;
    },
    
    #minor HTTP version or end of request line
    $s_req_http_minor => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR) {
            $parser->{state} = $s_req_line_almost_done;
            goto BREAK;
        }
        
        if ($ch eq $LF) {
            $parser->{state} = $s_header_field_start;
            goto BREAK;
        }
        
        #XXX allow spaces after digit?
        if (!IS_NUM($ch)) {
            SET_ERRNO($HPE_INVALID_VERSION, $parser);
            goto error;
        }
        
        $parser->{http_minor} *= 10;
        $parser->{http_minor} += $ch;
        
        if ($parser->{http_minor} > 999) {
            SET_ERRNO($HPE_INVALID_VERSION, $parser);
            goto error;
        }
        
        goto BREAK;
    },
    
    #end of request line
    $s_req_line_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch ne $LF) {
            SET_ERRNO($HPE_LF_EXPECTED, $parser);
            goto error;
        }
        
        $parser->{state} = $s_header_field_start;
        goto BREAK;
    },
    
    $s_header_field_start => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR) {
            $parser->{state} = $s_headers_almost_done;
            goto BREAK;
        }
        
        if ($ch eq $LF) {
            # they might be just sending \n instead of \r\n so this would be
            # the second \n to denote the end of headers
            $parser->{state} = $s_headers_almost_done;
            goto reexecute_byte;
        }
        
        my $c = TOKEN($ch);
        
        if (!$c) {
            SET_ERRNO($HPE_INVALID_HEADER_TOKEN, $parser);
            goto error;
        }
        
        MARK('header_field',$parser);
        
        $parser->{index} = 0;
        $parser->{state} = $s_header_field;
        
        if ($c eq 'c'){
            $parser->{header_state} = $h_C;
        } elsif ($c eq 'p') {
            $parser->{header_state} = $h_matching_proxy_connection;
        } elsif ($c eq 't'){
            $parser->{header_state} = $h_matching_transfer_encoding;
        } elsif ($c eq 'u'){
            $parser->{header_state} = $h_matching_upgrade;
        } else {
            $parser->{header_state} = $h_general;
        }
        goto BREAK;
    },
    
    $s_header_field => sub {
        my $parser = shift;
        my $ch = shift;
        
        my $c = TOKEN($ch);
        #breaking
        if ($c) {
            my $h_state = $parser->{header_state};
            if ($h_state == $h_general){
                #nothing
            }
            
            elsif ($h_state == $h_C){
                $parser->{index}++;
                $parser->{header_state} = ($c eq 'o' ? $h_CO : $h_general);
            }
            
            elsif ($h_state == $h_CO) {
                $parser->{index}++;
                $parser->{header_state} = ($c eq 'n' ? $h_CON : $h_general);
            }
            
            elsif ($h_state == $h_CON) {
                $parser->{index}++;
                if ($c eq 'n'){
                    $parser->{header_state} = $h_matching_connection;
                } elsif ($c eq 't'){
                    $parser->{header_state} = $h_matching_content_length;
                } else {
                    $parser->{header_state} = $h_general;
                }
            }
            
            #connection
            elsif ($h_state == $h_matching_connection){
                $parser->{index}++;
                if ($parser->{index} > sizeof($CONNECTION) - 1
                    || $c ne $CONNECTION[$parser->{index}]) {
                    $parser->{header_state} = $h_general;
                } elsif ($parser->{index} == sizeof($CONNECTION) - 2) {
                    $parser->{header_state} = $h_connection;
                }
            }
            
            #proxy-connection
            elsif ($h_state == $h_matching_proxy_connection){ 
                $parser->{index}++;
                if ($parser->{index} > sizeof($PROXY_CONNECTION)-1
                    || $c ne $PROXY_CONNECTION[$parser->{index}]) {
                    $parser->{header_state} = $h_general;
                } elsif ($parser->{index} == sizeof($PROXY_CONNECTION)-2) {
                    $parser->{header_state} = $h_connection;
                }
            }
            
            #content-length
            elsif ($h_state == $h_matching_content_length){
                $parser->{index}++;
                if ($parser->{index} > sizeof($CONTENT_LENGTH)-1
                    || $c ne $CONTENT_LENGTH[$parser->{index}]) {
                    $parser->{header_state} = $h_general;
                } elsif ($parser->{index} == sizeof($CONTENT_LENGTH)-2) {
                    $parser->{header_state} = $h_content_length;
                }
            }
            
            #transfer-encoding
            elsif ($h_state == $h_matching_transfer_encoding){
                $parser->{index}++;
                if ($parser->{index} > sizeof($TRANSFER_ENCODING)-1
                    || $c ne $TRANSFER_ENCODING[$parser->{index}]) {
                    $parser->{header_state} = $h_general;
                } elsif ($parser->{index} == sizeof($TRANSFER_ENCODING)-2) {
                    $parser->{header_state} = $h_transfer_encoding;
                }
            }
            
            #upgrade
            elsif ($h_state == $h_matching_upgrade){   
                $parser->{index}++;
                if ($parser->{index} > sizeof($UPGRADE)-1
                    || $c ne $UPGRADE[$parser->{index}]) {
                    $parser->{header_state} = $h_general;
                } elsif ($parser->{index} == sizeof($UPGRADE)-2) {
                    $parser->{header_state} = $h_upgrade;
                }
            }
            
            elsif ( $h_state == $h_connection ||
                     $h_state == $h_content_length ||
                     $h_state == $h_transfer_encoding||
                     $h_state == $h_upgrade ) {
                
                if ($ch ne ' ') { $parser->{header_state} = $h_general; }
            }
            
            else {
                die("Unknown header_state");
            }
            
            goto BREAK;
        }
        
        if ($ch eq ':') {
            $parser->{state} = $s_header_value_discard_ws;
            CALLBACK_DATA('header_field', $parser);
            goto BREAK;
        }
        
        if ($ch eq $CR) {
            $parser->{state} = $s_header_almost_done;
            CALLBACK_DATA('header_field', $parser);
            goto BREAK;
        }
        
        if ($ch eq $LF) {
            $parser->{state} = $s_header_field_start;
            CALLBACK_DATA('header_field', $parser);
            goto BREAK;
        }
        
        SET_ERRNO($HPE_INVALID_HEADER_TOKEN, $parser);
        goto error;
    },
    
    ##fallthrough here
    
    $s_header_value => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq $CR) {
            $parser->{state} = $s_header_almost_done;
            CALLBACK_DATA('header_value', $parser);
            goto BREAK;
        }
        
        if ($ch eq $LF) {
            $parser->{state} = $s_header_almost_done;
            CALLBACK_DATA_NOADVANCE('header_value', $parser) && goto error;
            goto reexecute_byte;
        }
        
        my $c = lc $ch;
        my $h_state = $parser->{header_state};
        if ($h_state == $h_general){
            #nothing
        }
        
        elsif ($h_state == $h_connection || $h_state == $h_transfer_encoding){
            die("Shouldn't get here.");
        }
        
        elsif ($h_state == $h_content_length) {
            my $t;
            if ($ch eq ' '){ goto out; }
            if (!IS_NUM($ch)) {
                SET_ERRNO($HPE_INVALID_CONTENT_LENGTH, $parser);
                goto error;
            }
            
            $t = $parser->{content_length};
            $t *= 10;
            $t += $ch;
            
            #Overflow? Test against a conservative limit for simplicity. */
            if (($ULLONG_MAX - 10) / 10 < $parser->{content_length}) {
                SET_ERRNO($HPE_INVALID_CONTENT_LENGTH, $parser);
                goto error;
            }
            
            $parser->{content_length} = $t;
        }
        
        #Transfer-Encoding: chunked
        elsif ($h_state == $h_matching_transfer_encoding_chunked){
            $parser->{index}++;
            if ($parser->{index} > sizeof($CHUNKED)-1 ||
                 $c ne $CHUNKED[$parser->{index}]) {
                $parser->{header_state} = $h_general;
            } elsif ($parser->{index} == sizeof($CHUNKED)-2) {
                $parser->{header_state} = $h_transfer_encoding_chunked;
            }
        }
        
        #looking for 'Connection: keep-alive'
        elsif ( $h_state == $h_matching_connection_keep_alive){
            $parser->{index}++;
            if ($parser->{index} > sizeof($KEEP_ALIVE)-1 ||
                 $c ne $KEEP_ALIVE[$parser->{index}]) {
                $parser->{header_state} = $h_general;
            } elsif ($parser->{index} == sizeof($KEEP_ALIVE)-2) {
                $parser->{header_state} = $h_connection_keep_alive;
            }
        }
        
        #looking for 'Connection: close'
        elsif ($h_state == $h_matching_connection_close){
            $parser->{index}++;
            if ($parser->{index} > sizeof($CLOSE)-1 ||
                 $c ne $CLOSE[$parser->{index}]) {
                $parser->{header_state} = $h_general;
            } elsif ($parser->{index} == sizeof($CLOSE)-2) {
                $parser->{header_state} = $h_connection_close;
            }
        }
        
        elsif ($h_state == $h_transfer_encoding_chunked ||
               $h_state == $h_connection_keep_alive ||
               $h_state == $h_connection_close){
            
            if ($ch ne ' ') { $parser->{header_state} = $h_general; }
        }
        
        else {
            $parser->{state} = $s_header_value;
            $parser->{header_state} = $h_general;
        }
        
        out : {
            goto BREAK;
        };
    },
    
    $s_header_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        $parser->{state} = $s_header_value_lws;
        goto BREAK;
    },
    
    $s_header_value_lws => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq ' ' || $ch eq "\t") {
            $parser->{state} = $s_header_value_start;
            goto reexecute_byte;
        }
        
        #finished the header
        my $h_state = $parser->{header_state};
        if ($h_state == $h_connection_keep_alive){
            $parser->{flags} |= $F_CONNECTION_KEEP_ALIVE;
        }
        
        elsif ($h_state == $h_connection_close){
            $parser->{flags} |= $F_CONNECTION_CLOSE;
        }
        
        elsif ($h_state == $h_transfer_encoding_chunked){
            $parser->{flags} |= $F_CHUNKED;
        }
        
        $parser->{state} = $s_header_field_start;
        goto reexecute_byte;
    },
    
    $s_header_value_discard_ws_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        $parser->{state} = $s_header_value_discard_lws;
        goto BREAK;
    },
    
    $s_header_value_discard_lws => sub {
        my $parser = shift;
        my $ch = shift;
        
        if ($ch eq ' ' || $ch eq "\t") {
            $parser->{state} = $s_header_value_discard_ws;
            goto BREAK;
        } else {
            #header value was empty
            MARK('header_value', $parser);
            $parser->{state} = $s_header_field_start;
            CALLBACK_DATA_NOADVANCE('header_value', $parser) && goto error;
            goto reexecute_byte;
        }
    },
    
    $s_headers_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        
        if ($parser->{flags} & $F_TRAILING) {
            #End of a chunked request */
            $parser->{state} = NEW_MESSAGE($parser);
            CALLBACK_NOTIFY('message_complete', $parser);
            goto BREAK;
        }
        
        $parser->{state} = $s_headers_done;
        
        #Set this here so that on_headers_complete() callbacks can see it
        $parser->{upgrade} = ($parser->{flags} & $F_UPGRADE ||
                               ($parser->{method} &&
                                $parser->{method} == $HTTP_CONNECT));
        
        #Here we call the headers_complete callback. This is somewhat
        #different than other callbacks because if the user returns 1, we
        #will interpret that as saying that this message has no body. This
        #is needed for the annoying case of recieving a response to a HEAD
        #request.
        
        #We'd like to use CALLBACK_NOTIFY_NOADVANCE() here but we cannot, so
        #we have to simulate it by handling a change in errno below.
        
        if ($parser->{cb}->{on_headers_complete}) {
            my $ret = $parser->{cb}->{on_headers_complete}->($parser);
            if (!defined $ret || $ret == 0) {
                
            } elsif ($ret == 1) {
                $parser->{flags} |= $F_SKIPBODY;
            } else {
                SET_ERRNO($HPE_CB_headers_complete, $parser);
                return $parser->{p} - $parser->{len}; # Error
            }
        }
        
        if (HTTP_PARSER_ERRNO($parser) != $HPE_OK) {
            return $parser->{p} - $parser->{len};
        }
        
        goto reexecute_byte;
    },
    
    $s_headers_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        
        $parser->{nread} = 0;
        
        #Exit, the rest of the connect is in a different protocol.
        if ($parser->{upgrade}) {
            $parser->{state} = NEW_MESSAGE($parser);
            CALLBACK_NOTIFY('message_complete', $parser);
            return ($parser->{p} - $parser->{len}) + 1;
        }
        
        if ($parser->{flags} & $F_SKIPBODY) {
            $parser->{state} = NEW_MESSAGE($parser);
            CALLBACK_NOTIFY('message_complete', $parser);
        } elsif ($parser->{flags} & $F_CHUNKED) {
            #chunked encoding - ignore Content-Length header
            $parser->{state} = $s_chunk_size_start;
        } else {
            if ($parser->{content_length} == 0) {
                #Content-Length header given but zero: Content-Length: 0\r\n */
                $parser->{state} = NEW_MESSAGE($parser);
                CALLBACK_NOTIFY('message_complete', $parser);
            } elsif ($parser->{content_length} != $ULLONG_MAX) {
                #Content-Length header given and non-zero
                $parser->{state} = $s_body_identity;
            } else {
                if ($parser->{type} == $HTTP_REQUEST ||
                     !http_message_needs_eof($parser)) {
                    #Assume content-length 0 - read the next
                    $parser->{state} = NEW_MESSAGE($parser);
                    CALLBACK_NOTIFY('message_complete', $parser);
                } else {
                    #Read body until EOF
                    $parser->{state} = $s_body_identity_eof;
                }
            }
        }
        goto BREAK;
    },
    
    $s_body_identity => sub {
        my $parser = shift;
        my $ch = shift;
        
        my $to_read = min($parser->{content_length},
                            ($parser->{len} - $parser->{p}));
        
        assert($parser->{content_length} != 0
             && $parser->{content_length} != $ULLONG_MAX);
        
        #The difference between advancing content_length and p is because
        #the latter will automaticaly advance on the next loop iteration.
        #Further, if content_length ends up at 0, we want to see the last
        #byte again for our message complete callback.
        MARK('body', $parser);
        $parser->{content_length} -= $to_read;
        $parser->{p} += $to_read - 1;
        #print Dumper $parser->{content_length};
        if ($parser->{content_length} == 0) {
            $parser->{state} = $s_message_done;
            
            #Mimic CALLBACK_DATA_NOADVANCE() but with one extra byte.
            #The alternative to doing this is to wait for the next byte to
            #trigger the data callback, just as in every other case. The
            #problem with this is that this makes it difficult for the test
            #harness to distinguish between complete-on-EOF and
            #complete-on-length. It's not clear that this distinction is
            #important for applications, but let's keep it for now.
            CALLBACK_DATA_('body', $parser,
                             $parser->{p} - $parser->{body_mark} + 1,
                             $parser->{p}) && goto error;
            
            goto reexecute_byte;
        }
        
        goto BREAK;
    },
    
    # read until EOF
    $s_body_identity_eof => sub {
        my $parser = shift;
        my $ch = shift;
        
        MARK('body', $parser);
        $parser->{p} = $parser->{len} - 1;
        goto BREAK;
    },
    
    $s_message_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        $parser->{state} = NEW_MESSAGE($parser);
        CALLBACK_NOTIFY('message_complete', $parser);
        goto BREAK;
    },
    
    $s_chunk_size_start => sub {
        my $parser = shift;
        my $ch = shift;
        
        assert($parser->{nread} == 1);
        assert($parser->{flags} & $F_CHUNKED);
        my $unhex_val = $unhex[ord($ch)];
        if ($unhex_val == -1) {
            SET_ERRNO($HPE_INVALID_CHUNK_SIZE, $parser);
            goto error;
        }
        
        $parser->{content_length} = $unhex_val;
        $parser->{state} = $s_chunk_size;
        goto BREAK;
    },
    
    $s_chunk_size => sub {
        my $parser = shift;
        my $ch = shift;
        
        my $t;
        
        assert($parser->{flags} & $F_CHUNKED);
        
        if ($ch eq $CR) {
            $parser->{state} = $s_chunk_size_almost_done;
            goto BREAK;
        }
        
        my $unhex_val = $unhex[ord($ch)];
        
        if ($unhex_val == -1) {
            if ($ch eq ';' || $ch eq ' ') {
                $parser->{state} = $s_chunk_parameters;
                goto BREAK;
            }
            
            SET_ERRNO($HPE_INVALID_CHUNK_SIZE, $parser);
            goto error;
        }
        
        $t = $parser->{content_length};
        $t *= 16;
        $t += $unhex_val;
        
        #Overflow? Test against a conservative limit for simplicity.
        if (($ULLONG_MAX - 16) / 16 < $parser->{content_length}) {
            SET_ERRNO($HPE_INVALID_CONTENT_LENGTH, $parser);
            goto error;
        }
        
        $parser->{content_length} = $t;
        goto BREAK;
    },
    
    $s_chunk_parameters => sub {
        my $parser = shift;
        my $ch = shift;
        
        assert($parser->{flags} & $F_CHUNKED);
        #just ignore this shit. TODO check for overflow
        if ($ch eq $CR) {
            $parser->{state} = $s_chunk_size_almost_done;
            goto BREAK;
        }
        goto BREAK;
    },
    
    $s_chunk_size_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        assert($parser->{flags} & $F_CHUNKED);
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        
        $parser->{nread} = 0;
        
        if ($parser->{content_length} == 0) {
            $parser->{flags} |= $F_TRAILING;
            $parser->{state} = $s_header_field_start;
        } else {
            $parser->{state} = $s_chunk_data;
        }
        goto BREAK;
    },
    
    $s_chunk_data => sub {
        my $parser = shift;
        my $ch = shift;
        
        my $to_read = min($parser->{content_length},
                             $parser->{len} - $parser->{p});
        
        assert($parser->{flags} & $F_CHUNKED);
        assert($parser->{content_length} != 0
          && $parser->{content_length} != $ULLONG_MAX);
        
        #See the explanation in s_body_identity for why the content
        #length and data pointers are managed this way.
        MARK('body', $parser);
        $parser->{content_length} -= $to_read;
        $parser->{p} += $to_read - 1;
        
        if ($parser->{content_length} == 0) {
            $parser->{state} = $s_chunk_data_almost_done;
        }
        
        goto BREAK;
    },
    
    $s_chunk_data_almost_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        assert($parser->{flags} & $F_CHUNKED);
        assert($parser->{content_length} == 0);
        STRICT_CHECK($ch ne $CR, $parser) && goto error;
        $parser->{state} = $s_chunk_data_done;
        CALLBACK_DATA('body', $parser);
        goto BREAK;
    },
    
    $s_chunk_data_done => sub {
        my $parser = shift;
        my $ch = shift;
        
        assert($parser->{flags} & $F_CHUNKED);
        STRICT_CHECK($ch ne $LF, $parser) && goto error;
        $parser->{nread} = 0;
        $parser->{state} = $s_chunk_size_start;
        goto BREAK;
    },
    
);

sub http_parser_init {
    my ($parser, $t) = @_;
    my $data = $parser->{data}; # preserve application data
    $parser->{nread} = 0;
    $parser->{data} = $data;
    $parser->{cb} ||= {};
    $parser->{type} ||= $t;
    $parser->{state} = ($parser->{type} == $HTTP_REQUEST ?
                         $s_start_req : ($parser->{type} == $HTTP_RESPONSE ?
                         $s_start_res : $s_start_req_or_res));
    
    $parser->{header_count} = -1;
    $parser->{start_header_count} = 0;
    $parser->{header_name} = '';
    
    $parser->{header_values} = [];
    $parser->{header_fields} = [];
    $parser->{headers} = {};
    
    $parser->{http_errno} = $HPE_OK;
}

sub http_parser_execute {
    
    my ($parser,$data,$len) = @_;
    #print Dumper $parser;
    
    my ($c, $ch);
    #my @data = split '', $data;
    #my @data = unpack 'c*', $data;
    
    ##marks
    $parser->{header_field_mark} = undef;
    $parser->{header_value_mark} = undef;
    $parser->{url_mark} = undef;
    $parser->{body_mark} = undef;
    $parser->{status_mark} = undef;
    $parser->{buffer} = $data;
    $parser->{p} = 0;
    $parser->{method} = 0;
    $parser->{len} = $len;
    
    #We're in an error state. Don't bother doing anything.
    if (HTTP_PARSER_ERRNO($parser) != $HPE_OK) {
        return 0;
    }
    
    if ($len == 0) {
        my $state = $parser->{state};
        
        if ($state == $s_body_identity_eof) {
            #Use of CALLBACK_NOTIFY() here would erroneously return 1 byte read if
            #we got paused.
            CALLBACK_NOTIFY_NOADVANCE('message_complete', $parser) &&
                goto error;
            
            return 0;
        } elsif ($state == $s_dead ||
                 $state == $s_start_req_or_res ||
                 $state == $s_start_res ||
                 $state == $s_start_req){
            
            return 0;
        } else {
            SET_ERRNO($HPE_INVALID_EOF_STATE,$parser);
            return 1;
        }
    }
    
    if ($parser->{state} == $s_header_field) {
        $parser->{header_field_mark} = undef;
    }
    
    if ($parser->{state} == $s_header_value) {
        $parser->{header_value_mark} = undef;
    }
    
    {
        my $state = $parser->{state};
        if ($state ==  $s_req_path ||
             $state == $s_req_schema ||
             $state == $s_req_schema_slash ||
             $state == $s_req_schema_slash_slash ||
             $state == $s_req_server_start ||
             $state == $s_req_server ||
             $state == $s_req_server_with_at ||
             $state == $s_req_query_string_start ||
             $state == $s_req_query_string ||
             $state == $s_req_fragment_start ||
             $state == $s_req_fragment) {
            
            $parser->{url_mark} = $data;
            
        } elsif ($state == $s_res_status) {
            $parser->{status_mark} = $data;
        }
    };
    
    $parser->{data} = 0;
    
    my $FALLTHROUGH = 0;
    for ($parser->{p} = 0; $parser->{p} < length $data; $parser->{p}++){
        $ch = substr( $data, $parser->{p}, 1);
        #$ch = $data[$parser->{p}];
        #DEBUG
        #map {
        #    print $data[$_];
        #} ($parser->{p} .. scalar @data - 1);
        #print $parser->{state}, "\n";
        
        if (PARSING_HEADER($parser->{state})) {
            ++$parser->{nread};
            #Don't allow the total size of the HTTP headers (including the status
            #line) to exceed HTTP_MAX_HEADER_SIZE. This check is here to protect
            #embedders against denial-of-service attacks where the attacker feeds
            #us a never-ending header that the embedder keeps buffering.
            #
            #This check is arguably the responsibility of embedders but we're doing
            #it on the embedder's behalf because most won't bother and this way we
            #make the web a little safer. HTTP_MAX_HEADER_SIZE is still far bigger
            #than any reasonable request or response so this should never affect
            #day-to-day operation.
            
            if ($parser->{nread} > $HTTP_MAX_HEADER_SIZE) {
                SET_ERRNO($HPE_HEADER_OVERFLOW,$parser);
                goto error;
            }
        }
        
        reexecute_byte: {
            if (my $action = $states{$parser->{state}}){
                $action->($parser,$ch);
            }
            
            #multi 1
            elsif ($parser->{state} == $s_req_schema ||
                $parser->{state} == $s_req_schema_slash ||
                $parser->{state} == $s_req_schema_slash_slash ||
                $parser->{state} == $s_req_server_start ) {
                
                if ($ch eq ' ' || $ch eq $CR || $ch eq $LF) {
                    #No whitespace allowed here
                    SET_ERRNO($HPE_INVALID_URL, $parser);
                    goto error;
                } else {
                    $parser->{state} = parse_url_char($parser->{state}, $ch);
                    if ($parser->{state} == $s_dead) {
                        SET_ERRNO($HPE_INVALID_URL, $parser);
                        goto error;
                    }
                }
                
                goto BREAK;
            }
            
            elsif ($parser->{state} == $s_req_server ||
                $parser->{state} == $s_req_server_with_at ||
                $parser->{state} == $s_req_path ||
                $parser->{state} == $s_req_query_string_start ||
                $parser->{state} == $s_req_query_string ||
                $parser->{state} == $s_req_fragment_start ||
                $parser->{state} == $s_req_fragment) {
                
                if ($ch eq ' ') {
                    $parser->{state} = $s_req_http_start;
                    CALLBACK_DATA('url', $parser) && goto error;
                } elsif ($ch eq $CR || $ch eq $LF) {
                    $parser->{http_major} = 0;
                    $parser->{http_minor} = 9;
                    $parser->{state} = ($ch eq $CR) ?
                        $s_req_line_almost_done :
                        $s_header_field_start;
                    
                    CALLBACK_DATA('url', $parser) && goto error;
                    
                } else {
                    $parser->{state} = parse_url_char($parser->{state}, $ch);
                    if ($parser->{state} == $s_dead) {
                        SET_ERRNO($HPE_INVALID_URL, $parser);
                        goto error;
                    }
                }
                
                goto BREAK;
            }
            ####end multi 1
            
            elsif ($parser->{state} == $s_header_value_discard_ws){
                if ($ch eq " " || $ch eq "\t") { goto BREAK; }
                
                if ($ch eq $CR) {
                    $parser->{state} = $s_header_value_discard_ws_almost_done;
                    goto BREAK;
                }
                
                if ($ch eq $LF) {
                    $parser->{state} = $s_header_value_discard_lws;
                    goto BREAK;
                }
                
            } # FALLTHROUGH
            
            $FALLTHROUGH = 1;
            if ($FALLTHROUGH || $parser->{state} == $s_header_value_start) {
                $FALLTHROUGH = 0;
                MARK('header_value', $parser);
                
                $parser->{state} = $s_header_value;
                $parser->{index} = 0;
                
                $c = lc $ch;
                
                my $h_state = $parser->{header_state}; 
                if ($h_state == $h_upgrade){
                    $parser->{flags} |= $F_UPGRADE;
                    $parser->{header_state} = $h_general;
                }
                
                #looking for 'Transfer-Encoding: chunked'
                elsif ($h_state == $h_transfer_encoding){
                    if ('c' eq $c) {
                        $parser->{header_state} = $h_matching_transfer_encoding_chunked;
                    } else {
                        $parser->{header_state} = $h_general;
                    }
                }
                
                elsif ($h_state == $h_content_length){
                    if (!IS_NUM($ch)) {
                        SET_ERRNO($HPE_INVALID_CONTENT_LENGTH, $parser);
                        goto error;
                    }
                    $parser->{content_length} = $ch;
                }
                
                elsif ($h_state == $h_connection) {
                    #looking for 'Connection: keep-alive'
                    if ($c eq 'k') {
                        $parser->{header_state} = $h_matching_connection_keep_alive;
                        #looking for 'Connection: close'
                    } elsif ($c eq 'c') {
                        $parser->{header_state} = $h_matching_connection_close;
                    } else {
                        $parser->{header_state} = $h_general;
                    }
                }
                
                else {
                    $parser->{header_state} = $h_general;
                }
                
                goto BREAK;
            }
            
            
            
            #die $parser->{state};
            #assert(0 && "unhandled state");
            SET_ERRNO($HPE_INVALID_INTERNAL_STATE, $parser);
            goto error;
            
        };
        
        BREAK : {
            ##auto parsing
            if ($parser->{state} == $s_header_value){
                if ($parser->{start_header_count}) {
                    $parser->{start_header_count} = 0;
                    $parser->{header_count}++;
                }
                
                $parser->{header_values}->[$parser->{header_count}] .= $ch;
                $parser->{headers}->{$parser->{header_name}} .= $ch if $parser->{header_name};
                $parser->{value} = $parser->{header_values}->[$parser->{header_count}];
            } elsif ($parser->{state} == $s_header_field) {
                if (!$parser->{start_header_count}) {
                    $parser->{header_name} = $ch;
                } else {
                    $parser->{header_name} .= $ch;
                }
                $parser->{header_fields}->[$parser->{header_count}+1] = $parser->{header_name};
                $parser->{value} = $parser->{header_name};
                $parser->{start_header_count} = 1;
            } elsif ($parser->{state} == $s_req_path || defined $parser->{url_mark}){
                $parser->{url} .= $ch;
                $parser->{value} = $parser->{url};
            } else {
                $parser->{value} = '';
                $parser->{header_name} = '';
            }
            
            1; #pass
        };
    }
    
    #Run callbacks for any marks that we have leftover after we ran our of
    #bytes. There should be at most one of these set, so it's OK to invoke
    #them in series (unset marks will not result in callbacks).
    
    #We use the NOADVANCE() variety of callbacks here because 'p' has already
    #overflowed 'data' and this allows us to correct for the off-by-one that
    #we'd otherwise have (since CALLBACK_DATA() is meant to be run with a 'p'
    #value that's in-bounds).
    
    assert((($parser->{header_field_mark} ? 1 : 0) +
              ($parser->{header_value_mark} ? 1 : 0) +
              ($parser->{url_mark} ? 1 : 0) +
              ($parser->{body_mark} ? 1 : 0) +
              ($parser->{status_mark} ? 1 : 0)) <= 1);
    
    CALLBACK_DATA_NOADVANCE('header_field', $parser) && goto error;
    CALLBACK_DATA_NOADVANCE('header_value', $parser) && goto error;
    CALLBACK_DATA_NOADVANCE('url', $parser) && goto error;
    CALLBACK_DATA_NOADVANCE('body', $parser) && goto error;
    CALLBACK_DATA_NOADVANCE('status', $parser) && goto error;
    
    return $len;
    
    error: {
        if (HTTP_PARSER_ERRNO($parser) == $HPE_OK) {
            SET_ERRNO($HPE_UNKNOWN);
        }
        
        if (my $error_cb = $parser->{cb}->{on_error}) {
            $error_cb->($parser,$parser->{http_errmsg});
        }
    }
    
    return $parser->{p} - ($len - $parser->{p});
}

1;

package Rum::Buffer;
use strict;
use warnings;
use utf8;
use Carp;
use POSIX 'ceil';
use Encode qw( encode_utf8 decode_utf8 encode decode );
use MIME::Base64;
use Rum::Utils;
use Data::Dumper;

sub import {
    utf8->import;
}

#=========================================================================
# Buffer toString
#=========================================================================
use overload '""' => \&inspect , fallback => 1;
use overload '&{}' => sub{
    my $self = shift;
    return sub{ $self->get(@_) }
} , fallback => 1;

use overload '@{}' => sub{
    my $self = shift;
    $self->toArray();
} , fallback => 1;

my $utils = Rum::Utils->new();


#=========================================================================
# Check available buffers
#=========================================================================
my %BUFFER_MAP = (
        hex => 1,  utf8 => 1, 'utf-8' => 1, ascii => 1,
        binary => 1, base64 => 1, ucs2 => 1, 'ucs-2' => 1,
        utf16le => 1, 'utf-16le' => 1, raw => 1 );

sub isEncoding {
    return $BUFFER_MAP{$_[0]};
}

#=========================================================================
# New Buffer Instance
#=========================================================================
sub new {
    my $class = shift;
    
    my $self = bless {}, $class;
    my ($subject, $encoding, $offset) = @_;
    
    $self->{buf}    = '';
    if ( $utils->isNumber($offset) ) {
        if (!isBuffer($subject)) {
            Carp::croak('First argument must be a Buffer when slicing');
        }
        
        $self->{length} = $utils->isNumber($encoding) && $encoding > 0 ? ceil($encoding) : 0;
        $self->{parent} = $subject->{parent} ? $subject->{parent} : $subject;
        $self->{offset} = $offset;
        
    } else {
        if ( $utils->isNumber($subject) ) {
            $self->{length} = $utils->isNumber($subject) && $subject > 0 ? ceil($subject) : 0;
        } elsif (!ref $subject){
            
        } elsif (ref $subject eq 'ARRAY'){
            $self->{length} = scalar @{$subject};
        } elsif ( _isBuffer($subject) ) {
            $self->{length} = $utils->isNumber($subject->{length})
                && $subject->{length} > 0 ? ceil( $subject->{length} ) : 0; 
        } else {
            Carp::croak('First argument needs to be a number array or string');
        }
        
        $self->{offset} = 0;
        
        #optimize by branching logic for new allocations
        if ( !$utils->isNumber($subject) ) {
            if (!ref $subject) {
                #We are a string
                $self->write($subject, 0, $encoding);
            } elsif ( _isBuffer($subject) ) {
                $subject->copy($self, 0, 0, $self->{length} );
            } elsif ( ref $subject eq 'ARRAY' ) {
                $self->setArray($subject);
            }
        }
    }
    return $self;
}

#=========================================================================
# Buffer Write
#=========================================================================
sub write {
    my ($self, $string, $offset, $length, $encoding) = @_;
    
    #allow write(string, encoding)
    if ( $utils->isString($offset) && !defined $length ) {
        $encoding = $offset;
        $offset = 0;
    #allow write(string, offset[, length], encoding)
    } elsif ( $utils->likeNumber($offset)) {
        $offset = $offset+0;
        if ( $utils->likeNumber($length) ) {
          $length = $length+0;
        } else {
          $encoding = $length;
          $length = undef;
        }
    }

    my $remaining = defined $self->{length} ? $self->{length} - ($offset || 0) : undef;
    if (!defined $length || $length > $remaining){
        $length = $remaining;
    }
    
    $encoding = lc ($encoding || 'utf8');
    $offset = $offset || 0;
    
    if ($encoding =~ /^(hex|utf8|utf-8|ascii|binary|base64)$/ ) {
        return $self->_write($string, $offset, $length, $encoding);
    } elsif ($encoding =~ /^(ucs2|ucs-2|utf16le|utf-16le)$/ ) {
        return $self->_write($string, $offset, $length, 'ucs2');
    } elsif ($encoding eq 'raw'){
        return $self->_write($string, $offset, $length, 'raw');
    }
    
    Carp::croak "Unknown encoding: $encoding";
}

#=========================================================================
# buffer fill
#=========================================================================
sub fill  {
    my ($self,$value, $start, $end) = @_;
    $value ||= 0;
    $start ||= 0;
    $end   ||= $self->length;
    
    if ( $utils->isNumber($value) ) {
        $value = chr $value;
    }

    Carp::croak('end < start') if $end < $start;
    
    #Fill 0 bytes; we're done
    return 0 if ($end == $start);
    return 0 if ($self->length == 0);
    
    if ($start < 0 || $start >= $self->length) {
        Carp::croak('start out of bounds');
    }

    if ($end < 0 || $end > $self->length) {
        Carp::croak('end out of bounds');
    }

    return $self->_fill($value,
        $start + $self->{offset},
        $end + $self->{offset} );
}

#=========================================================================
# Buffer toString
#=========================================================================
sub toString {
    my ($self, $encoding, $start, $end) = @_;
    $encoding = lc ($encoding || 'utf8');
    if ( !$utils->isNumber($start) || $start < 0) {
        $start = 0;
    } elsif ( $start > $self->{length} ) {
        $start = $self->{length};
    }
    
    if (!$utils->isNumber($end) || $end > $self->{length} ) {
        $end = $self->{length};
    } elsif ($end < 0) {
        $end = 0;
    }
    
    $start = $start + $self->{offset};
    $end   = $end   + $self->{offset};
    
    if ($encoding =~ /^(hex|utf8|utf-8|ascii|binary|base64)$/ ) {
        return $self->_toString($start, $end, $encoding);
    } elsif ($encoding =~ /^(ucs2|ucs-2|utf16le|utf-16le)$/ ) {
        return $self->_toString($start, $end, 'ucs2');
    } elsif ($encoding eq 'raw'){
        return $self->_toString($start, $end, 'raw');
    }
    
    Carp::croak "Unknown encoding: $encoding";
}

#=========================================================================
# Buffer Copy
#=========================================================================
sub copy {
    my ($self,$target, $target_start, $start, $end) = @_;
    #set undefined/NaN or out of bounds values equal to their default
    $target_start = 0 if !( $target_start >= 0 );
    $start = 0 if !$start || !($start >= 0);
    $end = $self->{length} if !$end || !( $end < $self->{length} );
    
    #Copy 0 bytes; we're done
    return 0 if ($end == $start ||
        $target->{length} == 0  ||
        $self->{length} == 0    ||
        $start > $self->{length} );
    
    Carp::croak('sourceEnd < sourceStart')   if $end < $start;
    Carp::croak('targetStart out of bounds') if $target_start >= $target->{length};
    
    if ( $target->{length} - $target_start < $end - $start) {
        $end = $target->{length} - $target_start + $start;
    }

    return $self->_copy($target,
        $target_start + ($target->{offset} || 0),
        $start + $self->{offset},
        $end + $self->{offset} );
}

#=========================================================================
# buffer slice
#=========================================================================
sub slice {
    my ($self,$start,$end) = @_;
    my $len = $self->length;
    $start = _clamp($start, $len, 0);
    $end = _clamp($end, $len, $len);
    my $buf = Rum::Buffer->new($end - $start);
    $self->copy($buf, 0, $start, $end);
    return $buf;
}

#=========================================================================
# buffer concat
#=========================================================================
sub concat {
    my ($self, $list, $length) = @_;
    if ( ref $list ne 'ARRAY' ) {
        Carp::croak('Usage: Buffer->concat(list, [length])');
    }
    
    my $list_length = scalar @{$list};
    
    if ($list_length == 0) {
        return Rum::Buffer->new(0);
    } elsif ($list_length == 1) {
        return $list->[0];
    }
    
    if ( !$utils->isNumber($length) ) {
        $length = 0;
        foreach my $buf ( @{$list} ) {
            $length += $buf->length;
        }
    }
    
    my $buffer = Rum::Buffer->new($length);
    my $pos = 0;
    foreach my $buf ( @{$list} ) {
        $buf->copy($buffer, $pos);
        $pos += $buf->length;
    }
    return $buffer;
}

#=========================================================================
# inspect buffer - overloaded with '""'
#=========================================================================
sub inspect {
    my $self = shift;
    my @r;
    my $str = substr $self->{buf},0,50;
    for my $c (split //, $str) {
        push @r, sprintf "%02x", ord $c;
    }
    
    my $ret = join ' ',@r;
    return "<Buffer $ret>";
}

#=========================================================================
# buffer set
#=========================================================================
sub set {
    my ($self,$index,$value) = @_;
    if ( $index > $self->{length} ){
        Carp::croak('index value out of range');
    }
    
    if ( !$utils->isNumber($value) ){
        $value = 0;
    }
    
    #this is how node seems to do it??
    #not as I expected to ascii conversion
    #I'm not sure if I'm doing it right though
    if ( $value > 255 ) {
        my $str = sprintf "%02x", $value;
        $value = substr $str,-2,2;
        $value = hex $value;
    }
    
    $value = chr($value);
    substr $self->{buf},$index,1, $value;
    return $self;
}

#=========================================================================
# get char at n position - overloaded with "&{}"
#=========================================================================
sub get {
    my ($self,$index) = @_;
    my $b = unpack("x$index a1", $self->{buf});
    return ord $b;
}

sub toArray  {
    my ($self) = @_;
    my @b = unpack("W*", $self->{buf});
    return wantarray ? @b : \@b;
}

#=========================================================================
# Helper Methods
#=========================================================================
sub _clamp {
    my ($index, $len, $defaultValue) = @_;
    return $defaultValue if (!$utils->isNumber($index));
    return $len if ($index >= $len);
    return $index if ($index >= 0);
    $index += $len;
    return $index if $index >= 0;
    return 0;
}

sub _isBuffer { return ref $_[0] eq 'Rum::Buffer' }
sub isBuffer  { return ref $_[1] eq 'Rum::Buffer' }
sub length    { shift->{length} }
sub offset    { shift->{offset} }

#=========================================================================
# Buffer action methods
#=========================================================================
{
    
    my $ret = {};
    
    #=====================================================================
    # Dispatch Tables
    #=====================================================================
    my $writeDispatch = {
        raw     => sub { _toBytes($_[0]) },
        utf8    => sub { _toBytes($_[0]) },
        'utf-8' => sub { _toBytes($_[0]) },
        ascii   => sub {
            #Rum::Buffer::Encode::decode_utf8($_[0]);
            $_[0] = asciiToBytes($_[0]);
        },
        hex     => sub { $_[0] = pack('H*',$_[0]) },
        base64  => sub {
            no warnings;
            $_[0] = decode_base64($_[0]);
        },
        binary  => sub {
            #Rum::Buffer::Encode::decode_utf8($_[0]);
            $_[0] = asciiToBytes($_[0]);
        },
        ucs2    => sub {
            #Rum::Buffer::Encode::decode_utf8($_[0]);
            $_[0] = encode("UCS-2LE", $_[0]);
        }
    };
    
    my $readDispatch = {
        raw     => sub { }, #nothing just return raw bytes
        utf8    => sub {
            Rum::Buffer::Encode::decode_utf8($_[0]);
        },
        'utf-8' => sub {
            Rum::Buffer::Encode::decode_utf8($_[0]);
        },
        hex     => sub { $_[0] = unpack('H*',$_[0]) },
        base64  => sub { $_[0] = encode_base64($_[0],'') },
        ucs2    => sub {
            $_[0] = decode("UCS-2LE", $_[0]);
        },
        binary  => sub {
            $_[0] = decode('ISO-8859-1',$_[0]);
        },
        ascii   => sub {
            my $string = '';
            my $off1 = 0;
            my $len1 = 8 * 1024;
            my $strlen = bytes::length $_[0];
            while ($off1 < $strlen){
                map {
                    $string .= chr($_ & 0x7f);
                } unpack("x$off1 W$len1",$_[0]);
                $off1 += $len1;
            }
            $_[0] = $string;
            undef $string;
        }
    };
    
    #=====================================================================
    # do Write
    #=====================================================================
    sub _write {
        my ($self,$str,$offset,$len,$encoding) = @_; 
        $encoding ||= 'utf8';
        $str ||= '';
        
        $writeDispatch->{$encoding}->($str);
        if (defined $len){
            $str = unpack("a$len", $str);
        }
        
        my $str_length = CORE::length $str;
        if ( defined $len && $len > $str_length ){
            $len = $str_length;
        }
        
        substr $self->{buf},$offset,($len || $str_length),$str;
        
        if (!$self->{length}){
            $self->{length} = $str_length;
        }
        
        undef $str;
        return $str_length;
    }
    
    #=====================================================================
    # do toString
    #=====================================================================
    sub _toString {
        my $self = shift;
        my $offset = shift;
        my $len = shift;
        my $encoding = shift || 'utf8';
        #local $ret->{str} = $self->{buf};
        local $ret->{str} = unpack("x$offset a$len", $self->{buf});
        $readDispatch->{$encoding}->($ret->{str});
        return $ret->{str};
    }
    
    #=====================================================================
    # do the copy
    # FIX : me we already checked parameters, so why to check again?
    #=====================================================================
    sub _copy {
        my $self = shift;
        my @args = @_;
        my $source = $self;
        my $target = $args[0];
        my $target_data = $target->{buf};
        my $target_length = $target->{length} || $source->{length};
        my $target_start = defined $args[1] ? $args[1] : 0;
        my $source_start = defined $args[2] ? $args[2] : 0;
        my $source_end = defined $args[3] ? $args[3] : 0;
        
        if ($source_end < $source_start){
            Carp::croak ('sourceEnd < sourceStart');
        }
        
        if ($source_end == $source_start){
            return 0;
        }
        
        if ($target_start >= $target_length){
            Carp::croak ('targetStart out of bounds');
        }
        
        if ($source_start >= $source->{length}){
            Carp::croak ('sourceStart out of bounds');
        }
        
        if ($source_end > $source->{length}){
            Carp::croak ('sourceEnd out of bounds');
        }
        
        my $to_copy = MIN(MIN($source_end - $source_start,
        $target_length - $target_start),
        $source->{length} - $source_start);
        
        my $str = unpack("x$source_start a$to_copy", $source->{buf});
        substr $target->{buf},$target_start, $to_copy, $str;
        
        undef $str;
        return $to_copy;
    }
    
    #=====================================================================
    # do filling
    #=====================================================================
    sub _fill  {
        my ($self, $chr, $start, $end) = @_;
        #my $str = chr ($chr) x ($end - $start);
        
        ##convert to bytes
        _toBytes($chr);
        
        my $str = asciiToBytes($chr) x ($end - $start);
        if (CORE::length $str > $self->length) {
            $str = substr $str,0,$self->length;
        }
        
        substr $self->{buf},$start,$end - $start,$str;
        undef $str;
        return $self;
    }
    
    #=====================================================================
    # helpers
    #=====================================================================
    sub _toBytes {
        use bytes;
        $_[0] = unpack('a*', $_[0]);
        no bytes;
    }
    
    sub slow_ascii {
        local $ret->{str2} = '';
        map {
            $ret->{str2} .= chr($_ & 0x7f);
        } unpack('W*',$_[0]);
        
        return $ret->{str2};
    }
    
    sub asciiToBytes {
        local $ret->{str2} = '';
        map {
            $ret->{str2} .= chr($_ & 0xff);
        } unpack('W*',$_[0]);
        
        return $ret->{str2};
    }
    
    sub setArray {
        my ($self,$arr) = @_;
        if (ref $arr eq 'ARRAY'){
            $self->{buf} = pack('W*', @$arr);
        }
        $self->{length} = scalar @$arr; 
        return 1;
    }
    
    sub MIN {
        my $a = shift;
        my $b = shift;
        return $a < $b ? $a : $b
    }
}

#=========================================================================
# Encod Package hack
#=========================================================================
# FIXME
# This is a quick hack
# Encode module
#=========================================================================
package Rum::Buffer::Encode; {
    use Encode qw[find_encoding is_utf8];
    my $utf8enc;
    sub decode_utf8($;$) {
        my ( $octets, $check ) = @_;
        return $octets if is_utf8($octets);
        return undef unless defined $octets;
        $octets .= '' if ref $octets;
        $check   ||= 0;
        $utf8enc ||= find_encoding('utf8');
        ##change encoding in place
        $_[0] = $utf8enc->decode( $octets, $check );
        undef $octets;
        return 1;
    }
}

1;

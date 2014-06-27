package Rum::StringDecoder;
use lib '../';

use strict;
use warnings;
use Rum::Buffer;
use Carp;
my $Buffer = 'Rum::Buffer';
use Rum::Buffer;

sub assertEncoding {
    my ($encoding) = @_;
    if ( $encoding && !Rum::Buffer::isEncoding($encoding) ) {
        Carp::croak('Unknown encoding: ' . $encoding);
    }
}

sub new {
    my ($class, $encoding) = @_;
    my $this = ref $class ? $class : bless {}, $class;
    $encoding = lc ($encoding || 'utf8');
    $encoding =~ s/[-_]//;
    $this->{encoding} = $encoding;
    assertEncoding($encoding);
    $this->{detectIncompleteChar} = \&detectIncompleteChar;
    if ($encoding eq 'utf8') {
        #CESU-8 represents each of Surrogate Pair by 3-bytes
        $this->{surrogateSize} = 3;
    } elsif ($encoding eq 'ucs2' || $encoding eq 'utf16le') {
        #UTF-16 represents each of Surrogate Pair by 2-bytes
        $this->{surrogateSize} = 2;
        $this->{detectIncompleteChar} = \&utf16DetectIncompleteChar;
    } elsif ($encoding eq 'base64'){
        #Base-64 stores 3 bytes in 4 chars, and pads the remainder.
        $this->{surrogateSize} = 3;
        $this->{detectIncompleteChar} = \&base64DetectIncompleteChar;
    } else {
        $this->{passwrite} = 1;
        return $this;
    }
    
    $this->{charBuffer} = Rum::Buffer->new(6);
    $this->{charReceived} = 0;
    $this->{charLength} = 0;
    return $this;
}

sub write {
    my ($this,$buffer) = @_;
    my $charStr = '';
    my $offset = 0;
    
    if (!ref $buffer) {
        $buffer = $Buffer->new($buffer);
    }
    
    
    $this->passThroughWrite($buffer) if $this->{passwrite};
    
    #if our last write ended with an incomplete multibyte character
    while ($this->{charLength}) {
        #determine how many remaining bytes this buffer has to offer for this char
        my $i = ($buffer->length >= $this->{charLength} - $this->{charReceived} ) ?
                $this->{charLength} - $this->{charReceived} :
                $buffer->length;
        
        #add the new bytes to the char buffer
        $buffer->copy($this->{charBuffer}, $this->{charReceived}, $offset, $i);
        $this->{charReceived} += ($i - $offset);
        $offset = $i;
        
        if ( $this->{charReceived} < $this->{charLength} ) {
            #still not enough chars in this buffer? wait for more ...
            return '';
        }
        
        #get the character that was split
        $charStr = $this->{charBuffer}->slice(0, $this->{charLength})->toString($this->{encoding});
        
        #lead surrogate (D800-DBFF) is also the incomplete character
        #my $charCode = $charStr.charCodeAt(charStr.length - 1);
        my $charCode = ord (substr $charStr, length($charStr) - 1, 1);
        if ($charCode >= 0xD800 && $charCode <= 0xDBFF) {
            $this->{charLength} += $this->{surrogateSize};
            $charStr = '';
            next;
        }
        
        $this->{charReceived} = $this->{charLength} = 0;
        
        #if there are no more bytes in this buffer, just emit our char
        return $charStr if ($i == $buffer->length);
        
        #otherwise cut off the characters end from the beginning of this buffer
        $buffer = $buffer->slice($i, $buffer->length);
        last;
    }

    my $lenIncomplete = $this->{detectIncompleteChar}->($this,$buffer);

    my $end = $buffer->length;
    if ($this->{charLength}) {
        #buffer the incomplete character bytes we got
        $buffer->copy($this->{charBuffer}, 0, $buffer->length - $lenIncomplete, $end);
        $this->{charReceived} = $lenIncomplete;
        $end -= $lenIncomplete;
    }

    $charStr .= $buffer->toString($this->{encoding}, 0, $end);

    $end = length($charStr) - 1;
    #my $charCode = charStr.charCodeAt(end);
    my $charCode = ord (substr $charStr, $end, 1);
    #lead surrogate (D800-DBFF) is also the incomplete character
    if ($charCode >= 0xD800 && $charCode <= 0xDBFF) {
        my $size = $this->{surrogateSize};
        $this->{charLength} += $size;
        $this->{charReceived} += $size;
        $this->{charBuffer}->copy($this->{charBuffer}, $size, 0, $size);
        my $charat = substr $charStr, length($charStr) - 1, 1;
        $this->{charBuffer}->write($charat, $this->{encoding} );
        return substr $charStr,0, $end;
    }

    #or just emit the charStr
    return $charStr;
}

sub detectIncompleteChar {
    my ($this,$buffer) = @_;
    #determine how many bytes we have to check at the end of this buffer
    my $i = ($buffer->length >= 3) ? 3 : $buffer->length;

    #Figure out if one of the last i bytes of our buffer announces an
    #incomplete char.
    for (; $i > 0; $i--) {
        my $c = $buffer->get($buffer->length - $i);
        
        #See http://en.wikipedia.org/wiki/UTF-8#Description
        
        #110XXXXX
        if ($i == 1 && $c >> 5 == 0x06) {
            $this->{charLength} = 2;
            last;
        }
        
        #1110XXXX
        if ($i <= 2 && $c >> 4 == 0x0E) {
            $this->{charLength} = 3;
            last;
        }
        
        #11110XXX
        if ($i <= 3 && $c >> 3 == 0x1E) {
            $this->{charLength} = 4;
            last;
        }
    }
    return $i;
}

sub passThroughWrite {
    my ($this,$buffer) = @_;
    return $buffer->toString($this->{encoding});
}

sub end  {
    my ($this,$buffer) = @_;
    my $res = '';
    if ($buffer && $buffer->length) {
        $res = $this->write($buffer);
    }

    if ( $this->{charReceived} ) {
        my $cr = $this->{charReceived};
        my $buf = $this->{charBuffer};
        my $enc = $this->{encoding};
        $res .= $buf->slice(0, $cr)->toString($enc);
    }
    return $res;
}


1;

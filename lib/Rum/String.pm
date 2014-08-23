package Rum::String;
use strict;
use warnings;
use Encode ();
use MIME::Base64;
use Data::Dumper;
my $local = {};

my $UTF8 = Encode::find_encoding("utf8");

sub IsValidString {
    my ($str,$enc) = @_;
    if ($enc eq 'HEX' && length($str) % 2 != 0){
        return 0;
    }
    #TODO(bnoordhuis) Add BASE64 check?
    return 1;
}

sub asciiToBytes {
    local $local->{str} = '';
    my $i = 0;
    for (my $i = 0; $i < length $_[0]; $i++) {
        my $ch = substr $_[0], $i, 1;
        $local->{str} .= chr(ord($ch) & 0x7f);
    }
    return $local->{str};
}

#$_[0] = buffer
#$_[1] = copy to string
#$_[2] = encoding
sub write {
    my $encoding = $_[2];
    
    if ($encoding eq 'buffer') {
        $_[1] = $_[0]->toString('raw');
    }
    
    elsif ($encoding eq 'ascii' ||
            $encoding eq 'binary' ) {
        
        $_[1] = asciiToBytes($_[0]);
    }
    
    elsif ($encoding eq 'utf8'){
        $_[1] = $UTF8->encode($_[0]);
    }
    
    elsif ($encoding eq 'base64'){
        $_[1] = decode_base64($_[0]);
    }
    
    elsif ($encoding eq 'hex'){
        $_[1] = pack "H*", $_[0];
    }
    
    elsif ($encoding eq 'UCS2'){
        $_[1] = Encode::encode("UCS-2LE", $_[0]);
    }
    
    else {
        die "unknown encoding " . $encoding;
    }
    
    return CORE::length $_[1];
}

sub encode {
    my ($str) = @_;
    
}

1;

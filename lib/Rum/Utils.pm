package Rum::Utils;
use strict;
use warnings;
use B  ();
use Scalar::Util 'looks_like_number';
use List::Util ();
use Data::Dumper;

my $ERRNO_MAP = {
    2 => 'ENOENT'
};

sub new {bless {},__PACKAGE__}
sub isNumber {
    my $self = shift;
    return 0 unless defined $_[0] && !ref $_[0];
    # From JSON::PP
    my $flags = B::svref_2object(\$_[0])->FLAGS;
    my $is_number = $flags & (B::SVp_IOK | B::SVp_NOK)
      and !($flags & B::SVp_POK) ? 1 : 0;

    return 1 if $is_number;
    return 0;
}

sub isString {
    my $self = shift;
    if ( defined $_[0] && !ref $_[0] && !$self->isNumber($_[0]) ) {
        return 1;
    }
    return 0;
}

sub typeof {
    my $self = shift;
    my $thing = shift;
    return 'undefined' if !defined $thing;
    return 'number' if $self->isNumber($thing);
    return 'string' if $self->isString($thing);
    my $ref = ref $thing;
    return 'array'    if $ref eq 'ARRAY';
    return 'hash'     if $ref eq 'HASH';
    return 'function' if $ref eq 'CODE';
    return 'object'   if $ref;
}

sub likeNumber { looks_like_number($_[1]) }

#The isFinite function returns true if number is any value other than NaN,
#negative infinity, or positive infinity. In those three cases, it returns false.
sub isinf    { shift; $_[0]==9**9**9 || $_[0]==-9**9**9 }
sub isNaN    { shift; ! defined( $_[0] <=> 9**9**9 ) }
sub signbit  { shift; substr( sprintf( '%g', $_[0] ), 0, 1 ) eq '-' }
sub isFinite {
    my ($self,$num) = @_;
    if ($self->isString($num) || !defined $num) {
        return 0;
    }
    
    if ($self->isinf($num) || $self->isNaN($num) || $self->signbit($num)) {
        return 1;
    }
    return 0;
}

sub isBuffer {
    my $self = shift;
    return ref $_[0] eq 'Rum::Buffer';
}

sub hasDomain {
    my $self = shift;
    my $this = shift;
    if (ref $this
        && $this->{domain}
        && ref $this->{domain} eq 'Rum::Domain') {
        return $this->{domain};
    }
    return 0;
}

sub isNullOrUndefined {
    my ($self,$arg) = @_;
    return !defined $arg;
}

sub isNull {
    my ($self,$arg) = @_;
    return !defined $arg;
}

sub isUndefined {
    return !defined $_[1];
}

sub isFunction {
    return ref $_[1] eq 'CODE';
}

sub isObject {
    return (ref $_[1] && ref $_[1] ne 'CODE');
}

sub min { List::Util::min($_[1]) }

sub _extend {
    shift;
    my ($origin, $add) = (shift, shift);
    #Don't do anything if add isn't an object
    if (!$add || !ref $add eq 'HASH' ) { return $origin };
    
    for (keys %{$add}) {
        $origin->{$_} = $add->{$_};
    }
    return $origin;
}

sub concat {
    shift;
    my @new = ();
    foreach my $arr (@_){
        if (ref $arr eq 'ARRAY') {
            foreach my $val (@{$arr}){
                push @new, $val;
            }
        } else {
            next;
        }
    }
    return \@new;
}

sub isArray {
    ref $_[1] eq 'ARRAY';
}

sub _errnoException {
    my ($err, $syscall, $original) = @_;
    if ($err < 0) {
        $err *= -1;
    }
    
    $syscall ||= '';
    $original ||=  '';
    
    my $saved_errno = $!;
    $! = $err + 0; #cast to number
    
    my $errname = $!;
    my $message = $syscall . ' ' . $errname;
    if ($original) {
        $message .= ' ' . $original;
    }
    
    my $e = Rum::Error->new($message);
    my@caller = caller(1);
    $e->{caller2} = \@caller;
    $e->{code} = $ERRNO_MAP->{$errname+0};
    $e->{errno} = $err + 0;
    $e->{syscall} = $syscall;
    $! = $saved_errno;
    return $e;
}

sub reduce {
    shift;
    my $this = shift;
    my $callback = shift;
    
    if ( !$this || ref $this ne 'ARRAY' ) {
      die('reduce called on undefined' );
    }
    
    if ( ref $callback ne 'CODE') {
        die( 'callback is not a function' );
    }
    
    my $t = $this;
    my $len = scalar @{$t};
    my $k = 0;
    my $value;
    
    if ( @_ >= 1 ) {
        $value = $_[0];
    } else {
        while ( $k < $len && !defined $t->[$k] ) { $k++ }; 
        if ( $k >= $len ) {
            die('Reduce of empty array with no initial value');
        }
        $value = $t->[ $k++ ];
    }
    
    for ( ; $k < $len ; $k++ ) {
        if ( defined $t->[$k] ) {
            $value = $callback->( $value, $t->[$k], $k, $t );
        }
    }
    
    return $value;
}

sub filter {
    shift;
    my $this = shift;
    my $fun = shift;
    
    if (!$this){
        die;
    }
    
    my $t = $this;
    my $len = scalar @{$t};
    if (ref $fun ne 'CODE'){
        die( 'callback is not a function' );
    }
    
    my $res = [];
    my $thisArg = @_ >= 1 ? $_[0] : 0;
    for (my $i = 0; $i < $len; $i++) {
        if ($t->[$i]) {
            my $val = $t->[$i];
            if ($fun->($val, $i, $t)){
                push @{$res}, $val;
            }
        }
    }
    
    return $res;
}

sub debuglog {
    shift;
    my $type = shift;
    
    my $uType = uc $type;
    if (!$ENV{RUM_DEBUG} || $ENV{RUM_DEBUG} !~ /$uType/i) {
        return sub {};
    }
    
    return sub {
        print STDERR $uType . " $$: ";
        for (@_){
            if (ref $_){
                print STDERR Dumper $_;
            } elsif (defined $_) {
                print STDERR $_ . " ";
            } else {
                print STDERR "undefined ";
            }
        }
        print STDERR "\n";
    };
}

sub BufferOrStringLength {
    return ref $_[1] ? $_[1]->length : length $_[1];
}

1;

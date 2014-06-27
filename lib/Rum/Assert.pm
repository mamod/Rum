package Rum::Assert;
use strict;
use warnings;
use Carp;
use Rum::Utils;
use Rum::TryCatch;
my $utils = 'Rum::Utils';
use Data::Dumper;

#=========================================================================
# fail
#=========================================================================
sub fail {
    my ($self, $actual, $expected, $message, $operator, $stackStartFunction) = @_;
    Rum::Assert::Error->new({
        message => $message,
        actual => $actual,
        expected => $expected,
        operator => $operator,
        stackStartFunction => $stackStartFunction
    })->throw();
}

#=========================================================================
# ok
#=========================================================================
sub ok {
    my ($self, $value, $message) = @_;
    $self->fail($value, 1, $message, '==', \&ok) if (!$value);
}

#=========================================================================
# equal
#=========================================================================
sub equal {
    my ($self, $actual, $expected, $message) = @_;
    my $test = 0;
    ##assert if they are of not same types
    if ($utils->typeof($actual) ne $utils->typeof($expected)) {
        $test = 0;
    } elsif ($utils->isString($actual) && $utils->isString($expected)) {
        $test = ($actual eq $expected);
    } else {
        $test = ($actual == $expected);
    }
    $self->fail($actual, $expected, $message, '==', \&equal) if !$test;
}

#=========================================================================
# notEqual
#=========================================================================
sub notEqual {
    my ($self, $actual, $expected, $message) = @_;
    my $test = 0;
    ##pass if not of same types
    if ($utils->typeof($actual) ne $utils->typeof($expected)) {
        $test = 1;
    } elsif ($utils->isString($actual) && $utils->isString($expected)) {
        $test = ($actual ne $expected);
    } else {
        $test = ($actual != $expected);
    }
    $self->fail($actual, $expected, $message, '!=', \&notEqual)  if !$test;
}

sub doesNotThrow {
    my $self = shift;
    $self->_throws(0,@_);
}

sub throws {
    my $self = shift;
    $self->_throws(1,@_);
}

sub expectedException {
    my ($actual, $expected) = @_;
    if (!$actual || !$expected) {
        return 0;
    }
    
    if (ref $expected eq 'Regexp') {
        return $actual =~ $expected;
    } elsif (ref $actual eq ref $expected) {
        return 1;
    } elsif ( $expected->($actual) ) {
        return 1;
    }
    
    return 0;
}

sub _throws {
    my ($self,$shouldThrow, $block, $expected, $message) = @_;
    my $actual = '';

    if ($utils->isString($expected)) {
        $message = $expected;
        $expected = undef;
    }

    try {
        $block->();
    } catch {
        $actual = $_;
    };
    
    $message = ($expected && ref $expected ne 'Regexp' && ref $expected eq 'HASH' && $expected->{name} ? ' (' . $expected->{name} . ').' : '.') .
            ($message ? ' ' . $message : '.' . $actual);

    if ($shouldThrow && !$actual) {
        $self->fail($actual, $expected, 'Missing expected exception' . $message);
    }

    if (!$shouldThrow && expectedException($actual, $expected)) {
        $self->fail($actual, $expected, 'Got unwanted exception' . $message);
    }
    
    #if ($shouldThrow && !expectedException($actual, $expected)) {
    #    $self->fail($actual, $expected, 'Got unwanted exception' . $message);
    #}
    
    if (($shouldThrow && $actual && $expected &&
      !expectedException($actual, $expected)) || (!$shouldThrow && $actual)) {
        die $actual;
    }
}

#=========================================================================
# Rum::Assert::Error package
#=========================================================================
package Rum::Assert::Error; {
    use strict;
    use warnings;
    use Data::Dumper;
    use base 'Rum::Error';
    sub new {
        my ($class, $options) = @_;
        my $this = bless {}, $class;
        $this->{name} = 'AssertionError';
        $this->{actual} = $options->{actual};
        $this->{expected} = $options->{expected};
        $this->{operator} = $options->{operator};
        if ($options->{message}) {
            $this->{message} = $options->{message};
            $this->{generatedMessage} = 0;
        } else {
            $this->{message} = getMessage($this);
            $this->{generatedMessage} = 1;
        }
        #var stackStartFunction = options.stackStartFunction || fail;
        #Error.captureStackTrace(this, stackStartFunction);
        return $this;
    }
    
    sub getMessage {
        my $self = shift;
        my $msg = $self->{actual};
        $msg .= ' ' . $self->{operator} if $self->{operator};
        $msg .= ' ' . $self->{expected} if $self->{expected};
        return $msg;
    }
    
}


1;

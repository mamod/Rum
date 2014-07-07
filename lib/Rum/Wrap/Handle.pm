package Rum::Wrap::Handle;
use strict;
use warnings;
use Data::Dumper;

my $kUnref = 1;
my $kCloseCallback = 2;

use base qw/Exporter/;
our @EXPORT = qw (
    close
    ref
    unref
);

sub HandleWrap {
    my $this = shift;
    $_[0]->{data} = $this;
    $this->{handle__} = $_[0];
}

sub close {
    my ($wrap,$cb) = @_;
    if (!$wrap || !$wrap->{handle__}) {
        return;
    }
    
    Rum::Loop::default_loop()->close($wrap->{handle__}, \&OnClose);
    undef $wrap->{handle__};
    if (ref $cb eq 'CODE') {
        $wrap->{onclose} = $cb;
        $wrap->{flags} |= $kCloseCallback;
    }
}

sub OnClose {
    my $handle = shift;
    my $wrap = $handle->{data};
    die "The wrap object should still be there" if !$wrap;
    #die "the handle pointer should be gone" if $wrap->{handle__};
    
    if ( $wrap->{flags} && ($wrap->{flags} & $kCloseCallback) ) {
        Rum::MakeCallback2($wrap, 'onclose');
    }
    
    undef $wrap;
}

sub unref {
    my $wrap = shift;
    if ($wrap && $wrap->{handle__}) {
        Rum::Loop::default_loop()->unref($wrap->{handle__});
        $wrap->{flags} |= $kUnref;
    }
}

sub ref {
    my $wrap = shift;
    if ($wrap && $wrap->{handle__}) {
        Rum::Loop::default_loop()->ref($wrap->{handle__});
        $wrap->{flags} &= ~$kUnref;
    }
}

1;

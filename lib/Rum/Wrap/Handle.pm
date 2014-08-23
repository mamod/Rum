package Rum::Wrap::Handle;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util 'weaken';
my $kUnref = 1;
my $kCloseCallback = 2;
my $loop = Rum::Loop::default_loop();

use base qw/Exporter/;
our @EXPORT = qw (
    close
    ref
    unref
    getHandleData
);

my $HANDLES = {};

sub getHandleData {
    my $handle = shift;
    return $HANDLES->{"$handle"};
}

sub HandleWrap {
    my $this = shift;
    my $handle = shift;
    $HANDLES->{"$handle"} = $this;
    $this->{handle__} = $handle;
}

sub close {
    my ($wrap,$cb) = @_;
    if (!$wrap || !$wrap->{handle__}) {
        return;
    }
    
    $loop->close($wrap->{handle__}, \&OnClose);
    $wrap->{handle__} = undef;
    if (ref $cb eq 'CODE') {
        $wrap->{onclose} = $cb;
        $wrap->{flags} |= $kCloseCallback;
    }
}

sub OnClose {
    my $handle = shift;
    my $wrap = getHandleData($handle);
    die "The wrap object should still be there" if !$wrap;
    die "the handle pointer should be gone" if $wrap->{handle__};
    if ( $wrap->{flags} && ($wrap->{flags} & $kCloseCallback) ) {
        Rum::MakeCallback2($wrap, 'onclose');
    }
    delete $HANDLES->{"$handle"};
    undef $wrap;
}

sub unref {
    my $wrap = shift;
    if ($wrap && $wrap->{handle__}) {
        $loop->unref($wrap->{handle__});
        $wrap->{flags} |= $kUnref;
    }
}

sub ref {
    my $wrap = shift;
    if ($wrap && $wrap->{handle__}) {
        $loop->ref($wrap->{handle__});
        $wrap->{flags} &= ~$kUnref;
    }
}

1;

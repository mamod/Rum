package Rum::Path;
use warnings;
use strict;
use Carp;
use Data::Dumper;
my $isWindows = $^O eq 'MSWin32';

if ($isWindows) {
    eval "use base 'Rum::Path::Win'";
    *splitPath = *Rum::Path::Win::splitPath;
} else {
    eval "use base 'Rum::Path::POSIX'";
    *splitPath = *Rum::Path::POSIX::splitPath;
}

sub new {
    bless {}, __PACKAGE__;
}

sub dirname {
    my ($self,$path) = @_;
    my @result = splitPath($path);
    my $root = $result[0],
    my $dir = $result[1];
    if (!$root && !$dir) {
        #No dirname whatsoever
        return '.';
    }
    if ($dir) {
        #It has a dirname, strip trailing slash
        $dir = substr $dir,0, length($dir) - 1;
    }
    return $root . $dir;
}

sub extname {
    my ($self,$path) = @_;
    return (splitPath($path))[3];
}

sub basename {
    my ($self, $path, $ext) = @_;
    my $f = (splitPath($path))[2];
    #TODO: make this comparison case-insensitive on windows?
    if ($ext && (substr $f, -1 * length $ext) eq $ext) {
        $f = substr $f, 0, length($f) - length($ext);
    }
    return $f;
}

1;

__END__

=head1 NAME

Rum::Path

=head1 SYNOPSIS

    use Rum::Path;
    
    my $path = Rum::Path->new();
    
    my $file = $path->resolve('./r/p/../file.txt');
    my $ext  = $file->extname($file);

=head1 DESCRIPTION

=head1 METHODS


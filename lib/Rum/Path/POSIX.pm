package Rum::Path::POSIX;
use Rum::Path::Utils;
use strict;
use warnings;
use Cwd();
my $CWD = Cwd::cwd();
use Data::Dumper;

sub sep {'/'};
sub delimiter {':'};

#'root' is just a slash, or nothing.
my $splitPathRe = qr/^(\/?|)([\s\S]*?)((?:\.{1,2}|[^\/]+?|)(\.[^.\/]*|))(?:[\/]*)$/;
sub splitPath {
    my ($filename) = @_;
    my @res = Rum::Path::Utils::exec($splitPathRe,$filename);
    return splice @res,1;
}

sub resolve {
    my $self = shift;
    my $resolvedPath = '';
    my $resolvedAbsolute = 0;
    my @args = @_;
    for (my $i = (scalar @args) - 1; $i >= -1 && !$resolvedAbsolute; $i--) {
        my $path = ($i >= 0) ? $args[$i] : $CWD;
        #Skip empty and invalid entries
        if (!$path) {
            next;
        }
        $resolvedPath = $path . '/' . $resolvedPath;
        $resolvedAbsolute = $path =~ m/^\//;
    }
    
    #At this point the path should be resolved to a full absolute path, but
    #handle relative paths to be safe (might happen when process.cwd() fails)
    #Normalize the path
    my @resolved = grep { $_ if $_ } split '/', $resolvedPath;
    $resolvedPath = join '/', Rum::Path::Utils::normalizeArray(\@resolved, !$resolvedAbsolute);
    return (($resolvedAbsolute ? '/' : '') . $resolvedPath) || '.';
}

sub normalize {
    my ($self,$path) = @_;
    my $isAbsolute = $path =~ m/^\//;
    my $trailingSlash = (substr $path,-1) eq '/';
    #Normalize the path
    my @resolved = grep { $_ if $_ } split '/', $path;
    $path = join '/', Rum::Path::Utils::normalizeArray(\@resolved, !$isAbsolute);
    if (!$path && !$isAbsolute) {
        $path = '.';
    }
    if ($path && $trailingSlash) {
        $path .= '/';
    }
    return ($isAbsolute ? '/' : '') . $path;
}

sub join {
    my $self = shift;
    my @paths = @_;
    my @norm = grep {$_ if $_} @paths;
    return $self->normalize( join('/', @norm) );
}

sub _trim {
    my @arr = @_;
    my $start = 0;
    foreach my $a (@arr) {
        last if ($a ne '');
        $start++;
    }
    my $end = scalar @arr - 1;
    while ($end >= 0) {
        last if ($arr[$end] ne '');
        $end--;
    }
    return () if ($start > $end);
    return splice @arr,$start, $end - $start + 1;
}

sub relative {
    my ($self,$from,$to) = @_;
    $from = substr resolve($self,$from),1;
    $to = substr resolve($self,$to),1;
    my @fromParts = _trim( split('/',$from) );
    my @toParts = _trim( split('/',$to) );   
    my $length = do {
        my $len = scalar @fromParts;
        my $len2 = scalar @toParts;
        $len < $len2 ? $len : $len2;
    };
    
    my $samePartsLength = $length;
    for (my $i = 0; $i < $length; $i++) {
        if ($fromParts[$i] ne $toParts[$i]) {
            $samePartsLength = $i;
            last;
        }
    }
    
    my @outputParts = ();
    for (my $i = $samePartsLength; $i < scalar @fromParts; $i++) {
        push @outputParts, ('..');
    }
    
    push @outputParts, ( splice(@toParts,$samePartsLength) );
    return CORE::join '/',@outputParts;
}

1;

__END__


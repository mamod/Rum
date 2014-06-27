package Rum::Path::Win;
use Rum::Path::Utils;
use strict;
use warnings;
use Cwd();

my $splitDeviceRe =   qr/^([a-zA-Z]:|[\\\/]{2}[^\\\/]+[\\\/]+[^\\\/]+)?([\\\/])?([\s\S]*?)$/;
my $splitTailRe   =   qr/^([\s\S]*?)((?:\.{1,2}|[^\\\/]+?|)(\.[^.\/\\]*|))(?:[\\\/]*)$/;
my $CWD = Cwd::cwd();

sub sep {'\\'};
sub delimiter {';'};

sub splitPath {
    my ($filename) = @_;
    my @result = Rum::Path::Utils::exec($splitDeviceRe,$filename);
    my $device = ($result[1] || '') . ($result[2] || '');
    my $tail = $result[3] || '';
    #Split the tail into dir, basename and extension
    my @result2 = Rum::Path::Utils::exec($splitTailRe,$tail);
    my $dir = $result2[1];
    my $basename = $result2[2];
    my $ext = $result2[3];
    return ($device, $dir, $basename, $ext);
}

sub isAbsolute {
    my ($path) = @_;
    my @result = Rum::Path::Utils::exec($splitDeviceRe,$path);
    my $device = $result[1] || '';
    my $isUnc = $device && $device !~ /^.:/;
    ##UNC paths are always absolute
    return !!$result[2] || $isUnc;
}

sub normalizeUNCRoot {
    my $device = shift;
    $device =~ s/^[\\\/]+//;
    $device =~ s/[\\\/]+/\\/g;
    return '\\\\' . $device;
}

sub resolve {
    my $self = shift;
    my $resolvedDevice = '';
    my $resolvedTail = '';
    my $resolvedAbsolute = 0;
    my $isUnc;
    my @args = @_;
    for (my $i = (scalar @args) - 1; $i >= -1; $i--) {
        my $path;
        if ($i >= 0) {
            $path = $_[$i];
        } elsif (!$resolvedDevice) {
            $path = $CWD;
        } else {
            ##TODO
        }
        
        ## skip empty paths
        if (!$path) {
            next;
        }
        
        my @result = Rum::Path::Utils::exec($splitDeviceRe,$path);
        my $device = $result[1] || '';
        $isUnc = $device && $device !~ /^.:/;
        my $isAbsolute = isAbsolute($path);
        my $tail = $result[3];
        if ($device &&
            $resolvedDevice &&
            ( lc $device ne lc $resolvedDevice ) ) {
            #This path points to another device so it is not applicable
            next;
        }
        
        if (!$resolvedDevice) {
            $resolvedDevice = $device;
        }
        if (!$resolvedAbsolute) {
            $resolvedTail = $tail . '\\' . $resolvedTail;
            $resolvedAbsolute = $isAbsolute;
        }
        if ($resolvedDevice && $resolvedAbsolute) {
            last;
        }
    }
    
    #Convert slashes to backslashes when `resolvedDevice` points to an UNC
    #root. Also squash multiple slashes into a single one where appropriate.
    if ($isUnc) {
        $resolvedDevice = normalizeUNCRoot($resolvedDevice);
    }
    
    my @resolvedTail = grep {$_ if $_} split /[\\\/]+/, $resolvedTail;
    @resolvedTail = Rum::Path::Utils::normalizeArray(\@resolvedTail,!$resolvedAbsolute);
    $resolvedTail = join '\\',@resolvedTail;
    my $ret = ($resolvedDevice . ($resolvedAbsolute ? '\\' : '') . $resolvedTail) || '.';
    return $ret;
}

sub normalize {
    my ($self,$path) = @_;
    my @result = Rum::Path::Utils::exec($splitDeviceRe,$path);
    my $device = $result[1] || '';
    my @device = split '',$device;
    my $isUnc = @device && $device[1] ne ':';
    my $isAbsolute = !!$result[2] || $isUnc;
    my $tail = $result[3];
    my $trailingSlash = $tail =~ /[\\\/]$/;
    #If device is a drive letter, we'll normalize to lower case.
    if (@device && $device[1] eq ':') {
        $device = lc $device;
    }
    
    my @tail = grep {$_ if $_} split /[\\\/]+/, $tail;
    @tail = Rum::Path::Utils::normalizeArray(\@tail,!$isAbsolute);
    $tail = join '\\', @tail;
    if (!$tail && !$isAbsolute) {
        $tail = '.';
    }
    if ($tail && $trailingSlash) {
        $tail .= '\\';
    }
    #Convert slashes to backslashes when `device` points to an UNC root.
    #Also squash multiple slashes into a single one where appropriate.
    if ($isUnc) {
        $device = normalizeUNCRoot($device);
    }
    
    return $device . ($isAbsolute ? '\\' : '') . $tail;
}

sub join {
    my $self = shift;
    my @paths = grep {$_ if $_} @_;
    my $joined = join '\\', @paths;
    if ( @paths && $paths[0] !~ /^[\\\/]{2}[^\\\/]/ ) {
        $joined =~ s/^[\\\/]{2,}/\\/;
    }
    return $self->normalize($joined);
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
    $from = $self->resolve($from);
    $to = $self->resolve($to);
    #windows is not case sensitive
    my $lowerFrom = lc $from;
    my $lowerTo = lc $to;
    my @toParts = _trim(split(/\\/, $to));
    my @lowerFromParts = _trim(split(/\\/,$lowerFrom));
    my @lowerToParts = _trim(split(/\\/,$lowerTo));
    my $length = do {
        my $len = scalar @lowerFromParts;
        my $len2 = scalar @lowerToParts;
        $len < $len2 ? $len : $len2;
    };
    
    my $samePartsLength = $length;
    for (my $i = 0; $i < $length; $i++) {
        if ($lowerFromParts[$i] ne $lowerToParts[$i]) {
            $samePartsLength = $i;
            last;
        }
    }
    if ($samePartsLength == 0) {
        return $to;
    }
    
    my @outputParts = ();
    for (my $i = $samePartsLength; $i < scalar @lowerFromParts; $i++) {
        push @outputParts, ('..');
    }
    
    push @outputParts, ( splice(@toParts,$samePartsLength) );
    return CORE::join '\\',@outputParts;
}

1;

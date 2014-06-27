package Rum::Path::Utils;
use strict;
use warnings;

#==========================================================================
# javascript like exec function
# TODO : Move to Rum::Utils 
#==========================================================================
sub exec {
    my ($expr,$string) = @_;
    my @m = $string =~ $expr;
    #javascript exe method adds the whole matched strig
    #to the results array as index[0]
	if (@m){
		unshift @m, substr $string,$-[0],$+[0];
    }
    return @m;
}

sub normalizeArray {
    my ($parts, $allowAboveRoot) = @_;
    #if the path tries to go above the root, `up` ends up > 0
    my @parts = @{$parts};
    my $up = 0;
    for (my $i = (scalar @parts) - 1; $i >= 0; $i--) {
        my $last = $parts->[$i];
        if ($last eq '.') {
            splice @parts, $i, 1;
        } elsif ($last eq '..') {
            splice @parts, $i, 1;
            $up++;
        } elsif ($up) {
            splice @parts, $i, 1;
            $up--;
        }
    }

    #if the path is allowed to go above the root, restore leading ..s
    if ($allowAboveRoot) {
        while ($up--) {
            unshift @parts, ('..');
        }
    }
    return @parts;
}

1;

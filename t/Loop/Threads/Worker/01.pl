use strict;
use warnings;

return sub {
    my $req = shift;
    my $args = shift;
    foreach my $arg (@{$args}) {
        print $arg . "\n";
        $req->notify($arg);
        select undef,undef,undef,.1;
    }
    return [4,5,6];
};

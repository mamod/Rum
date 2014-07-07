use strict;
use warnings;
use Data::Dumper;
use IO::Handle;

return sub {
    my $req = shift;
    my $args = shift;
    my $counter = 3;
    
    while ($counter > 0) {
        $counter--;
        print Dumper "nested.pl";
        $req->notify($counter);
        select undef,undef,undef,.5;
    }
    
    return 200;
};

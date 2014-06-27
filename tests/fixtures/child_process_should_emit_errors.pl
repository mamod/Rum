#use Rum;
use Data::Dumper;
open(my $fh, '>', undef) or die $!;
print STDERR Dumper \%ENV;
#sleep 5;
exit 2;

1;

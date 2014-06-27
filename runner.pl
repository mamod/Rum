#!perl
use lib './lib';
use Rum;
use Rum::Module;

my $rum = Rum->new();
$rum->run(@ARGV);

1;

__END__


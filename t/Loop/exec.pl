use Data::Dumper;
use IO::Handle;
my $io = IO::Handle->new();


sub open_file {
    $io->fdopen($ARGV[0],"r") or exit 2;
}

open_file();

print Dumper \@ARGV;

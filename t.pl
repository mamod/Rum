use strict;
use warnings;
use lib './lib';
use Rum;
use Rum::Loop;
use FindBin qw($Bin);
use Data::Dumper;
use TAP::Harness;
use File::Find 'find';

$| = 1;
print "\n#--------------------------------------------#";
print "\n# Rum apps TESTS                             #";
print "\n#--------------------------------------------#";

print "\n";

my %args = (
    verbosity => 0,
    #lib     => [ 'lib', 'blib/lib', 'blib/arch' ],
    timer => 1,
    color => 1
);

my $harness = TAP::Harness->new( \%args );

my @tests = ();

if (!@ARGV) {
    push @ARGV, 'Loop';
}


for my $file (@ARGV){
    $file = './t/' . $file;
    if (-d $file) {
        find(sub{
            my $file = $File::Find::name;
            if ($file =~ /\.t$/) {
                push @tests,$file;
            }
        }, $file);
    } elsif (-f $file){
        push @tests, $file;
    }
}

$harness->runtests(@tests);

1;

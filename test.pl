use strict;
use warnings;
use lib './lib';
use Rum;
use FindBin qw($Bin);
use Data::Dumper;
use TAP::Harness;
use File::Find 'find';

$| = 1;
print "\n#--------------------------------------------#";
print "\n# Rum app TESTS                              #";
print "\n#--------------------------------------------#";

print "\n";
chmod 0777, 'rum.sh' or die $!;

my %args = (
    verbosity => 0,
    #lib     => [ 'lib', 'blib/lib', 'blib/arch' ],
    exec => \&_tests,
    timer => 1,
    color => 1
);

my $harness = TAP::Harness->new( \%args );

sub _tests {
    my ( $harness, $test_file ) = @_;
    my $runner = "$Bin/runner.pl";
    return [ "perl", $runner, $test_file ];
}

my @tests = ();

for my $file (@ARGV){
    $file = './tests/' . $file;
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

if (!@ARGV) {
    find(sub{
        my $file = $File::Find::name;
        if ($file =~ /\.t$/) {
            push @tests,$file;
        }
    },'./tests');
}



$harness->runtests(@tests);

1;

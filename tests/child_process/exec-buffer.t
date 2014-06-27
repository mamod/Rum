use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;

my $assert = Require('assert');
my $exec = Require('child_process')->{exec};
my $os = Require('os');
my $success_count = 0;

my $str = 'hello';

my $EOL = $os->{EOL};

#default encoding
my $child = $exec->("echo " . $str, sub {
    my ($err, $stdout, $stderr) = @_;
    ok(!ref $stdout, 'Expected stdout to be a string');
    ok(!ref $stderr, 'Expected stderr to be a string');
    is($str . $EOL, $stdout);
    $success_count++;
});

#no encoding (Buffers expected)
$child = $exec->("echo " . $str, {
    encoding => undef
}, sub {
    my ($err, $stdout, $stderr) = @_;
    ok(ref $stdout eq 'Rum::Buffer', 'Expected stdout to be a Buffer');
    ok(ref $stderr eq 'Rum::Buffer', 'Expected stderr to be a Buffer');
    is($str . $EOL, $stdout->toString());
    $success_count++;
});

process->on('exit', sub {
    is(2, $success_count);
    done_testing(7);
});

1;

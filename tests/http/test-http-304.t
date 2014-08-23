use Rum;
use Data::Dumper;
use Test::More;
my $common = Require('../common');
my $assert = Require('assert');

my $http = Require('http');
my $childProcess = Require('child_process');

my $s = $http->createServer(sub {
    my ($this, $request, $response) = @_;
    $response->writeHead(304);
    $response->end();
});

$s->listen($common->{PORT}, sub {
    $childProcess->exec('curl -i http://127.0.0.1:' . $common->{PORT} . '/',
        sub {
            my ($err, $stdout, $stderr) = @_;
            if ($err) {
                plan skip_all => 'curl required to run this test'
            }
            
            $s->close();
            print STDERR 'curled response correctly' . "\n";
            ok ($stdout =~ /HTTP\/1\.1 304 Not Modified/);
        }
    );
});

print ('Server running at http://127.0.0.1:' . $common->{PORT} . '/' . "\n");

process->on('exit', sub {
    done_testing(1);
});

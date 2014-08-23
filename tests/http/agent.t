use Rum;
use Test::More;

my $common = Require('../common');
my $http = Require('http');

my $server = $http->Server( sub {
    my ($this, $req, $res) = @_;
    $res->writeHead(200);
    $res->end("hello world\n");
});

my $responses = 0;
my $N = 10;
my $M = 10;

$server->listen($common->{PORT}, sub {
    for (my $i = 0; $i < $N; $i++) {
        setTimeout( sub {
            for (my $j = 0; $j < $M; $j++) {
                $http->get({ port => $common->{PORT}, path => '/' }, sub {
                    my ($this, $res) = @_;
                    printf("%d %d\n", $responses, $res->{statusCode});
                    if (++$responses == $N * $M) {
                        print('Received all responses, closing server', "\n");
                        $server->close();
                    }
                    $res->resume();
                })->on('error', sub {
                    my $this = shift;
                    my $e = shift;
                    print('Error! ', $e->{message}, "\n");
                    fail $e->{message};
                    $server->close();
                });
            }
        }, $i);
    }
});

process->on('exit', sub {
    is($N * $M, $responses);
    done_testing();
});

1;

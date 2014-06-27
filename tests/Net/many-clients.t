use Rum;
use Test::More;

my $assert = Require('assert');
my $net = Require('net');
my $common = Require('../common');

#settings
my $bytes = 1024 * 40;
my $concurrency = 100;
my $connections_per_client = 5;

#measured
my $total_connections = 0;

my $body = '';
for (my $i = 0; $i < $bytes; $i++) {
    $body .= 'C';
}

my $server = $net->createServer(sub {
    my $this = shift;
    my $c = shift;
    diag('connected');
    $total_connections++;
    diag('# ' . $total_connections);
    $c->write($body);
    $c->end();
});

sub runClient {
    my $callback = shift;
    my $client = $net->createConnection($common->{PORT});
    
    $client->{connections} = 0;
    
    #$client->setEncoding('utf8');
    $client->on('connect', sub {
        diag('c');
        $client->{recved} = '';
        $client->{connections} += 1;
    });

    $client->on('data', sub {
        my $this = shift;
        my $chunk = shift;
        $this->{recved} .= $chunk->toString();
    });

    $client->on('end', sub {
        $client->end();
    });

    $client->on('error', sub {
        my $this = shift;
        my $e = shift;
        diag('Error');
        diag $e->{message};
        $e->throw();
    });

    $client->on('close', sub {
        my ($this, $had_error) = @_;
        diag('.');
        is(0, $had_error);
        is($bytes, length $client->{recved});

        if ($client->{fd}) {
            diag($client->{fd});
        }
        ok(!$client->{fd});
    
        if ($this->{connections} < $connections_per_client) {
            $this->connect($common->{PORT});
        } else {
            $callback->();
        }
    });
}

$server->listen($common->{PORT}, sub {
    my $finished_clients = 0;
    for (my $i = 0; $i < $concurrency; $i++) {
        runClient(sub {
            if (++$finished_clients == $concurrency){ $server->close() }
        });
    }
});

process->on('exit', sub {
    is($connections_per_client * $concurrency, $total_connections);
    diag('okay!');
    done_testing();
});


1;


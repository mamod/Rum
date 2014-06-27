use Rum;
use Test::More;
my $common = Require('../common');
my $net = Require('net');
my $assert = Require('assert');

my $sock = $net->Socket()->new();

my $PORT = $common->{PORT};

my $server; $server = $net->createServer()->listen($PORT, sub {
    
    ok(!$sock->{readable});
    ok(!$sock->{writable});
    $assert->equal($sock->readyState, 'closed');
   
    
    $sock->connect($PORT, sub {
        is($sock->{readable}, 1);
        is($sock->{writable}, 1);
        is($sock->readyState, 'open');
        
        $sock->end();
        ok(!$sock->{writable});
        is($sock->readyState, 'readOnly');
        
        $server->close();
        $sock->on('close', sub {
            ok(!$sock->{readable});
            ok(!$sock->{writable});
            is($sock->readyState, 'closed');
        });
    });
    
    is($sock->readyState, 'opening');
    
});

$sock->on('error', sub {
    my $self = shift;
    my $e = shift;
    die( $e->{message} );
});

process->on('exit',sub{
    done_testing(11);
});

1;

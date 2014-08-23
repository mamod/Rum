use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $http = Require('http');

my $bufferSize = 17 * 1024 * 1;
my $measuredSize = 0;

my $buffer = Buffer->new($bufferSize);

sub debug {
    print @_, "\n";
}


#FIXME:
#for (my $i = 0; $i < $buffer->length; $i++) {
#    $buffer->set($i,($i % 256));
#}

$buffer->fill('~');

my $web; $web = $http->Server( sub {
    my ($this, $req, $res) = @_;
    $web->close();
    
    debug(Dumper $req->{headers});
    
    my $i = 0;
    
    $req->on('data', sub {
        my ($this, $d) = @_;
        process->stdout->write(',');
        $measuredSize += $d->length;
        for (my $j = 0; $j < $d->length; $j++) {
            fail($buffer->($i) . '!=' . $d->($j)) if ($buffer->($i) != $d->($j));
            $i++;
        }
    });
    
    $req->on('end', sub {
        $res->writeHead(200);
        $res->write('thanks');
        $res->end();
        debug('response with \'thanks\'');
    });
    
    $req->{connection}->on('error', sub {
        my $self = shift;
        my $e = shift;
        debug('http server-side error: ' . $e->{message});
        $e->throw;
    });
});

my $gotThanks = 0;

$web->listen($common->{PORT}, sub {
    debug('Making request');
    my $req = $http->request({
        port => $common->{PORT},
        method => 'GET',
        path => '/',
        headers => { 'content-length' => $buffer->length }
    }, sub {
        my ($this, $res) = @_;
        debug('Got response');
        $res->setEncoding('utf8');
        $res->on('data', sub {
            my ($this, $string) = @_;
            is('thanks', $string);
            $gotThanks = 1;
        });
    });
    $req->end($buffer);
});

process->on('exit', sub {
    is($measuredSize, $bufferSize);
    ok($gotThanks);
    done_testing();
});




1;

use Rum;
my $http = Require('http');

my $options = {
    host => 'localhost',
    path => '/',
    port => '9090',
    headers => {'custom' => 'Custom Header Demo works'}
};

my $callback = sub {
    my ($this, $response) = @_;
    my $str = '';
    $response->on('data', sub {
        my ($this, $chunk) = @_;
        $str .= $chunk->toString;
    });
    
    $response->on('end', sub {
        print $str . "\n";
    });
};

my $req = $http->request($options, $callback);
$req->end();

1;

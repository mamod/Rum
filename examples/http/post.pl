use Rum;

my $http = Require('http');
my $postHTML = 
  '<html><head><title>Post Example</title></head>' .
  '<body>' .
  '<form enctype="multipart/form-data" method="post">' .
  'Input 1: <input name="input1"><br>' .
  'Input 2: <input name="input2"><br>' .
  'Input 3: <input type="file" name="datafile" size="40"><br>' .
  '<input type="submit">' .
  '</form>' .
  '</body></html>';

$http->createServer( sub {
    my ($this, $req, $res) = @_;
    my $body = "";
    
    $req->on('data', sub  {
        my ($this, $chunk) = @_;
        $body .= $chunk->toString;
    });
    
    $req->on('end', sub {
        print 'POSTed: ' . $body . "\n";
        $res->writeHead(200);
        $res->end($postHTML);
    });
})->listen(9090);

1;

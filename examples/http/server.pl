use Rum;

my $http = Require("http");
my $server = $http->createServer( sub {
    my ($this, $request, $response) = @_;
    print $request->{url}, "\n";
    $response->writeHead(200, {"Content-Type" => "text/html"});
    $response->write("<!DOCTYPE \"html\">");
    $response->write("<html>");
    $response->write("<head>");
    $response->write("<title>Hello World Page</title>");
    $response->write("</head>");
    $response->write("<body>");
    $response->write("Hello World!");
    $response->write("</body>");
    $response->write("</html>");
    $response->end();
});

$server->listen(9090);

1;

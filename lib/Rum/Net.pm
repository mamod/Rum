package Rum::Net;
use lib '../';
use strict;
use warnings;
use Rum 'module';
use Rum::Net::Server;
use Data::Dumper;
Rum::exports()->{createServer} = Rum::exports()->{Server} = sub {
    return Rum::Net::Server->new(@_);
};

Rum::exports()->{connect} = Rum::exports()->{createConnection} = sub {
    my @args = Rum::Net::Socket::normalizeConnectArgs(@_);
    my $s = Rum::Net::Socket->new($args[0]);
    return $s->connect(@args);
};

Rum::exports()->{Socket} = 'Rum::Net::Socket';

1;

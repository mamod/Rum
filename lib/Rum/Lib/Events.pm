package Rum::Lib::Events;
use strict;
use warnings;
use Rum 'module';
use Rum::Events;

our $usingDomains = 0;
our $domain;

module->{exports} = 'Rum::Events';

sub EventEmitter {
    return 'Rum::Events';
}

1;

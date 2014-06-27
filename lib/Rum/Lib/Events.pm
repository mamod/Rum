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

#sub new {
#    my $class = shift;
#    my $this = {};
#    $this->{domain} = undef;
#    if ($usingDomains) {
#        #if there is an active domain, then attach to it.
#        $domain = $domain || Require('domain');
#        #if ($domain->{active} && !(this instanceof domain.Domain)) {
#        #    $this->{domain} = $domain->{active};
#        #}
#    }
#   
#    $this->{_events} ||= {};
#    $this->{_maxListeners} ||= undef;
#    bless $this,'Rum::Events';
#}

1;

__END__

=head1 NAME

Rum::Events::EventEmitter

=head1 DESCRIPTION

This is a package exporter for Rum::Events module to be used with Rum apps, do not use directly
you need to check L<Rum::Events> instead

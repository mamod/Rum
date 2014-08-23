package Rum::DNS;
use Rum qw[exports Require];
use Rum::TryCatch;
use Socket qw[AF_INET AF_INET6 AF_UNIX inet_ntop inet_aton];
my $net = Require('net');
use Data::Dumper;

my $isWin = $^O =~ /win/i;

##detect supported inet_ntop
eval "inet_ntop(AF_INET, 1)";
my $no_inet_ntop = ($@ =~ /not implemented/i);

sub _isIP {
    my $address = shift;
    my $ip_address = inet_aton $address;
    return 4 if $no_inet_ntop;
    if (inet_ntop AF_INET, $ip_address){
        return 4;
    }
    if (inet_ntop AF_INET6, $ip_address){
        return 6;
    }
}

exports->{lookup} = sub {
    my ($hostname, $family, $callback) = @_;
    if (@_ == 2) {
        $callback = $family;
        $family = 0;
    } elsif (!$family) {
        $family = 0;
    } else {
        $family = +$family;
        if ($family != 4 && $family != 6) {
            Rum::Error->new('invalid argument: `family` must be 4 or 6')->throw();
        }
    }
    
    if (!$hostname) {
        $callback->(undef, undef, $family == 6 ? 6 : 4);
        return {};
    }
    
    my $matchedFamily = _isIP($hostname);
    if ($matchedFamily) {
        $callback->(undef, $hostname, $matchedFamily);
        return {};
    }
    
    die;
    
};

1;

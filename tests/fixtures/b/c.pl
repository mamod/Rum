use Rum;
use Test::More;

my $d = Require('./d');

my $package = Require('./package');

is('world', $package->{hello});

#diag('load fixtures/b/c.js');

my $string = 'C';

exports->{SomeClass} = sub {

};

exports->{C} = sub {
    return $string;
};

exports->{D} = sub {
    return $d->D();
};

process->on('exit', sub {
    $string = 'C done';
    #diag('b/c.pl exit');
});

1;

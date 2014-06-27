use Rum;
use Test::More;

#diag('load fixtures/b/d.pl');

my $string = 'D';

exports->{D} = sub {
    return $string;
};

process->on('exit', sub {
    $string = 'D done';
});

1;

use Rum;
my $c = Require('./b/c');

#console.error('load fixtures/a.js');

my $string = 'A';

exports->{SomeClass} = $c->SomeClass;

exports->{A} = sub {
    return $string;
};

exports->{C} = sub {
    return $c->C();
};

exports->{D} = sub {
    return $c->D();
};

exports->{number} = 42;

process->on('exit', sub {
    $string = 'A done';
});

1;

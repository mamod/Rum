use strict;
use warnings;
use lib '../../lib';
use Rum::Loop::Queue;
use Test::More;
use Data::Dumper;

my $q = QUEUE_INIT(1);
ok QUEUE_EMPTY($q);

# insert tail
QUEUE_INSERT_TAIL($q, QUEUE_INIT('foo'));

ok !QUEUE_EMPTY($q);

is QUEUE_HEAD($q)->{data}, 'foo';

QUEUE_REMOVE(QUEUE_HEAD($q));
ok QUEUE_EMPTY($q);


## insert head
QUEUE_INSERT_TAIL($q, QUEUE_INIT('bar'));

ok !QUEUE_EMPTY($q);

is QUEUE_HEAD($q)->{data}, 'bar';

QUEUE_REMOVE(QUEUE_HEAD($q));
ok QUEUE_EMPTY($q);

{
    ## insert multi TAIL
    QUEUE_INSERT_TAIL($q, QUEUE_INIT('foo'));
    QUEUE_INSERT_TAIL($q, QUEUE_INIT('bar'));
    QUEUE_INSERT_TAIL($q, QUEUE_INIT('buzz'));
    ok !QUEUE_EMPTY($q);
    
    my $head = QUEUE_HEAD($q);
    is $head->{data}, 'foo';
    QUEUE_REMOVE($head);
    
    ok !QUEUE_EMPTY($q);
    
    $head = QUEUE_HEAD($q);
    is $head->{data}, 'bar';
    QUEUE_REMOVE($head);
    
    ok !QUEUE_EMPTY($q);
    
    $head = QUEUE_HEAD($q);
    is $head->{data}, 'buzz';
    QUEUE_REMOVE($head);
    
    ok QUEUE_EMPTY($q);
}

{
    ## insert multi HEAD
    QUEUE_INSERT_HEAD($q, QUEUE_INIT('foo'));
    QUEUE_INSERT_HEAD($q, QUEUE_INIT('bar'));
    QUEUE_INSERT_HEAD($q, QUEUE_INIT('buzz'));
    ok !QUEUE_EMPTY($q);
    
    my $head = QUEUE_HEAD($q);
    is $head->{data}, 'buzz';
    QUEUE_REMOVE($head);
    
    ok !QUEUE_EMPTY($q);
    
    $head = QUEUE_HEAD($q);
    is $head->{data}, 'bar';
    QUEUE_REMOVE($head);
    
    ok !QUEUE_EMPTY($q);
    
    $head = QUEUE_HEAD($q);
    is $head->{data}, 'foo';
    QUEUE_REMOVE($head);
    
    ok QUEUE_EMPTY($q);
}

{
    ## insert multi HEAD+TAIL
    QUEUE_INSERT_HEAD($q, QUEUE_INIT('foo'));
    QUEUE_INSERT_TAIL($q, QUEUE_INIT('bar'));
    QUEUE_INSERT_HEAD($q, QUEUE_INIT('buzz'));
    ok !QUEUE_EMPTY($q);
    
    my $head = QUEUE_HEAD($q);
    is $head->{data}, 'buzz';
    QUEUE_REMOVE($head);
    
    ok !QUEUE_EMPTY($q);
    
    $head = QUEUE_HEAD($q);
    is $head->{data}, 'foo';
    QUEUE_REMOVE($head);
    
    ok !QUEUE_EMPTY($q);
    
    $head = QUEUE_HEAD($q);
    is $head->{data}, 'bar';
    QUEUE_REMOVE($head);
    
    ok QUEUE_EMPTY($q);
}

{
    my @qq = ('foo','bar','buzz');
    QUEUE_INSERT_HEAD($q, QUEUE_INIT($qq[0]));
    QUEUE_INSERT_HEAD($q, QUEUE_INIT($qq[1]));
    my $q3 = QUEUE_INIT($qq[2]);
    QUEUE_INSERT_HEAD($q, $q3);
    ok !QUEUE_EMPTY($q);
    
    my $i = 0;
    my @deep;
    my @rev = reverse @qq;
    QUEUE_FOREACH($q, sub {
        is $_->{data}, $rev[$i++];
        push @deep, $_->{data};
        QUEUE_REMOVE($q3) if $i == 0;
        
        QUEUE_REMOVE($_);
    });
    is $i, 3;
    is_deeply (\@deep,\@rev);
    ok QUEUE_EMPTY($q);
}

done_testing();
1;

use strict;
use warnings;
use Rum::RBTree;
use Test::More;

{
    
    my $expected = [1,2,3,10];
    
    my $tree = Rum::RBTree->new(sub{
        return $_[0] - $_[1];
    });
    
    ok($tree->insert(1));
    ok(!$tree->insert(1));
    
    ok($tree->insert(2));
    ok($tree->insert(3));
    
    ok($tree->remove(2));
    ok(!$tree->remove(2));
    
    $tree->insert(10);
    
    ok($tree->insert(2));
    
    is($tree->min, 1);
    is($tree->max, 10);
    
    my @got;
    while (my $v = $tree->min()){
        push @got,$v;
        $tree->remove($v);
    }
    
    is_deeply(\@got, $expected);
}

{
    my $hash1 = {
        id => 1
    };
    
    my $hash2 = {
        id => 2
    };
    
    my $tree = Rum::RBTree->new(sub{
        my ($a,$b) = @_;
        return $a->{id} - $b->{id};
    });
    
    ok($tree->insert($hash1));
    ok(!$tree->insert($hash1));
    ok($tree->insert($hash2));
    
    is($tree->min, $hash1);
    is($tree->max, $hash2);
    
    ok($tree->remove($hash1));
    ok($tree->remove($hash2));
    
    ok(!$tree->min);
    ok(!$tree->max);
}

{
    my $hash1 = {
        id => 1
    };
    
    my $hash2 = {
        id => 2
    };
    
    my $tree = Rum::RBTree->new(sub{
        my ($a,$b) = @_;
        return $b->{id} - $a->{id};
    });
    
    $tree->insert($hash1);
    $tree->insert($hash1);
    $tree->insert($hash2);
    
    is($tree->min, $hash2);
    is($tree->max, $hash1);
}

{
    
    my $tree = Rum::RBTree->new(sub{
        my ($a,$b) = @_;
        return 0 if ref $a eq ref $b;
        return 1;
        
        if (ref $b eq ref $a) {
            return 0;
        }
        return 1;
    });
    
    ok($tree->insert({hi=>'ff'}));
    ok(!$tree->insert({hi=>'ff'}));
    ok($tree->insert('Me'));
    ok(!$tree->insert('You'));
    ok($tree->insert([1]));
    ok(!$tree->insert([2]));
    
    is(ref $tree->max(),'HASH');
    is(ref $tree->min(),'ARRAY');
}

done_testing();

1;

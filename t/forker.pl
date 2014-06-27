use Rum::Forker;
use Test::More;

{
    my @got;
    my @expected;
    my $fork = Rum::Forker->new({
        child => sub {
            ##sleep fro sometime
            select undef,undef,undef,.01;
            my $data = shift;
            return 2 * $data;
        },
        parent => sub {
            my $data = shift;
            ok($data);
            push @got,$data;
        },
        max => 5
    });
    
    for (1 .. 500){
        my $n = $_;
        $fork->add($n);
        push @expected, (2 * $n);
    }
    
    $fork->loop();
    
    ##because order is not guranteed
    @got = sort @got;
    @expected = sort @expected;
    
    is_deeply(\@got, \@expected);
}


{
    my @got;
    my $fork = Rum::Forker->new({
        child => sub {
            return $$;
        },
        parent => sub {
            my $data = shift;
            push @got,$data;
        },
        ##one child process
        max => 1
    });
    
    for (1 .. 50){
        my $n = $_;
        $fork->add({});
    }
    
    $fork->loop();
    
    ##all should have the same pid
    my $id = $got[0];
    
    foreach my $pid (@got) {
        is ($pid,$id);
    }   
}

done_testing(551);

1;

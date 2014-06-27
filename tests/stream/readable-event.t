use Rum;
use Test::More;
my $Readable = Require('stream')->Readable;

#First test, not reading when the readable is added.
#make sure that on('readable', ...) triggers a readable event.
{
  
    my $r = $Readable->new({
        highWaterMark => 3
    });

    my $_readCalled = 0;
    $r->{_read} = sub  {
        $_readCalled = 1;
    };

    #This triggers a 'readable' event, which is lost.
    $r->push(Buffer->new('blerg'));

    my $caughtReadable = 0;
    setTimeout( sub {
        #we're testing what we think we are
        ok(!$r->{_readableState}->{reading});
        $r->on('readable', sub {
            $caughtReadable = 1;
        });
    });

    process->on('exit', sub {
        #we're testing what we think we are
        ok(!$_readCalled);
        ok($caughtReadable);
        #diag('ok 1');
    });
};



#second test, make sure that readable is re-emitted if there's
#already a length, while it IS reading.
{
  

    my $r = $Readable->new({
        highWaterMark => 3
    });

    my $_readCalled = 0;
    $r->{_read} = sub {
        $_readCalled = 1;
    };
    
    #This triggers a 'readable' event, which is lost.
    $r->push(Buffer->new('bl'));
    
    my $caughtReadable = 0;
    setTimeout( sub {
        #test we're testing what we think we are
        ok($r->{_readableState}->{reading});
        $r->on('readable', sub {
            $caughtReadable = 1;
        });
    });
    
    process->on('exit', sub {
        #we're testing what we think we are
        ok($_readCalled);
        ok($caughtReadable);
        #diag('ok 2');
    });
};


#Third test, not reading when the stream has not passed
#the highWaterMark but *has* reached EOF.
{
    
    my $r = $Readable->new({
        highWaterMark => 30
    });
  
    my $_readCalled = 0;
    $r->{_read} = sub {
        $_readCalled = 1;
    };
  
    #This triggers a 'readable' event, which is lost.
    $r->push(Buffer->new('blerg'));
    $r->push(undef);
  
    my $caughtReadable = 0;
    setTimeout( sub {
        #assert we're testing what we think we are
        ok(!$r->{_readableState}->{reading});
        $r->on('readable', sub {
            $caughtReadable = 1;
        });
    });
  
    process->on('exit', sub {
        #we're testing what we think we are
        ok(!$_readCalled);
        ok($caughtReadable);
        #diag('ok 3');
    });
};

process->on('exit',sub{
    done_testing(9);
});

1;

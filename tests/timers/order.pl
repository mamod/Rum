use Rum;
use Test::More;


######timeout inside interval with lower timeout value
{
    my $i = 0;
    my $x = 0;
    my $int; $int = setInterval(sub{
        $i++;
        diag "xxxxxxx interval called";
        setTimeout(sub{
            diag "ssssssssss called $x";
           $x++;
        },5);
        if ($i>=10) {
            clearInterval($int);
        }
        
    },10);
    
    process->on('exit',sub{
        is($i,$x);
    });
}


######process nextTick inside interval block
#{
#    my $i = 0;
#    my $x = 0;
#    my $int; $int = setInterval(sub{
#        $i++;
#        process->nextTick(sub{
#            $x++;
#        },5);
#        
#        if ($i>=10) {
#            clearInterval($int);
#        }
#        
#    },10);
#    
#    process->on('exit',sub{
#        is($i,$x);
#    });
#}
#
#######timeout inside interval with higer timeout value
#{
#    my $i = 0;
#    my $x = 0;
#    my $int; $int = setInterval(sub{
#        $i++;
#        setTimeout(sub{
#           $x++;
#        },10);
#        
#        if ($i>=10) {
#            clearInterval($int);
#        }
#        
#    },5);
#    
#    
#    process->on('exit',sub{
#        is($i,$x);
#    });
#}
#
#
#######interval inside timeout with higer timeout value
#{
#    my $i = 0;
#    my $x = 0;
#    
#    for ( 0 .. 10 ){
#        setTimeout(sub{
#            $i++;
#            setInterval(sub{
#               $x++;
#               clearInterval($_[0]);
#            },10);
#        },5);
#    }
#    
#    process->on('exit',sub{
#        is($i,$x);
#    });
#}
#
#
#######interval inside timeout with lower timeout value
#{
#    my $i = 0;
#    my $x = 0;
#    
#    for ( 0 .. 10 ){
#        setTimeout(sub{
#            $i++;
#            setInterval(sub{
#               $x++;
#               clearInterval($_[0]);
#            },5);
#        },10);
#    }
#    
#    process->on('exit',sub{
#        is($i,$x);
#    });
#}


process->on('exit',sub{
    done_testing();
});

1;

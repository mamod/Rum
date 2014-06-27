use Rum;
use Test::More;
my $assert = Require('assert');
my $max = 5;
for ( 0 .. $max ){
    my $i = 0;
    my $timeout = $_;
    setTimeout(sub{
        $i++;
        setTimeout(sub{
            $i++;
            setTimeout(sub{
                $i++;
                setTimeout(sub{
                    $i++;
                    setTimeout(sub{
                        $i++;
                    },$timeout);
                },$timeout);
            },$timeout);
        },$timeout);
    },$timeout);
    
    my $x = 0;
    setInterval(sub{
        #print('dddd'."\n");
        is(++$x,$i);
        clearInterval($_[0]) if ($x == 5);
    },$timeout);
}

process->on('exit',sub{
    done_testing(  ($max * 5)+5 );
});

1;

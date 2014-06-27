package Rum::IO;
use strict;
use warnings;
use Data::Dumper;
use Socket;
use IO::Handle;
use IO::Select;

my ($CHILD,$PARENT);
my $SELECT = IO::Select->new();
my $HANDLES = {};
my $FDS = 0;
sub handles { $HANDLES }
sub initaite {
    return 1;
    socketpair($CHILD, $PARENT, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
    ||  die "socketpair: $!";
    
    $CHILD->autoflush(1);
    $PARENT->autoflush(1);
    $CHILD->blocking(0);
    $PARENT->blocking(0);
    $SELECT->add($CHILD);
    
    if (my $pid = fork()) {
        close $PARENT;
        my $interval; $interval = Rum::setInterval(sub{
            my @ready = $SELECT->can_read(0);
            foreach my $ready (@ready) {
                my $line = <$ready>;
                my @t = split '#',$line;
                my $todo = $t[0];
                my $fd = $t[1];
                $HANDLES->{$fd}->{active} = 1;
                #$to->();
                #Rum::process()->nextTick($to);
            }
            
            if (!keys %{$HANDLES}) {
                Rum::clearInterval($interval);
                kill 9, $pid;
            } else {
            }
            
        },10);
    } else {
        close $CHILD;
        while (my $line = <$PARENT>) {
            #sleep 1;
            my @t = split '#',$line;
            my $todo = $t[0];
            my $fd = $t[1];
            
            print $PARENT "$todo#$fd#\n";
        }
    }
}

sub ADD {
    my $action = shift;
    my $fd = shift;
    my $sub = shift;
    $HANDLES->{$fd} = {
        active => 0,
        cb => $sub
    };
    
    #Rum::process()->nextTick(sub{
    #    print $CHILD "read#$fd#\n";
    #});
    
    Rum::process()->nextTick($sub);
}

1;

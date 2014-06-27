package Rum::Forker;
use warnings;
use strict;
use IO::Handle;
use Storable qw(freeze thaw store_fd fd_retrieve);
use Data::Dumper;
use Socket;
use IO::Select;
my $select = IO::Select->new();
my $POOL = {};

sub debug {
    #print $_[0] . "\n";
}

sub new {
    my ($class,$data) = @_;
    my $childSub = $data->{child};
    my $parentSub = $data->{parent};
    my $self = bless {
        pool => [],
        queue => [],
        children => [],
        forks => 0,
        max => $data->{max} || 6,
        child => $childSub,
        parent => $parentSub
    }, $class;
    $self->_createPipes();
    $select->add($self->{childfh});
    return $self;
}

sub _createPipes {
    my $self = shift;
    socketpair($self->{childfh}, $self->{parentfh}, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
    ||  die "socketpair: $!";
    $self->{childfh}->autoflush(1);
    $self->{parentfh}->autoflush(1);
    $self->{parentfh}->blocking(0);
    $self->{childfh}->blocking(0);
}

sub _fork {
    my $self = shift;
    my $id = $self->{forks};
    my $pool = Rum::Forker::Pool->new($id);
    
    if (my $pid = fork()) {
        $pool->{pid} = $pid;
        push @{$self->{children}}, $pid;
        return $pool;
    } else {
        #close $self->{childfh};
        my $fh = $pool->{fh};
        local $/ = "\n";
        local $SIG{ALRM} = sub {
            seek $fh, 0,0;
            my $got = fd_retrieve($fh);
            my $ret = $self->{child}->($got->{data});
            my $t = {
                data => $ret,
                id => $id
            };
            $t = freeze $t;
            $self->{parentfh}->write($t . '[END]');
            
            seek $fh, 0,0;
            return;
        };
        
        while (1) {
            sleep 1;
        }
    }
    
    return $pool;
}

sub add {
    my $self = shift;
    my $data = shift;
    my $t = {
        data => $data,
    };
    
    push @{$self->{queue}}, $data;
    return $self;
}

sub _getFreePool {
    my $self = shift;
    my $pool = shift @{$self->{pool}};
    
    if ($pool) {
        debug "got free pool " . $pool->{id};
    } elsif ($self->{forks} < $self->{max} ) {
        $self->{forks}++;
        $pool = $self->_fork();
        debug "creating new pool " . $pool->{id};
    }
    
    if ($pool){
        $POOL->{$pool->{id}} = $pool;
    }
    
    return $pool;
}

sub loop {
    my $self = shift;
    local $/ = '[END]';
    while (1) {
        #select undef,undef,undef,0.001;
        my $data = $self->{queue}->[0];
        if ($data) {
            my $pool = $self->_getFreePool();   
            if ($pool) {
                my $data = shift @{$self->{queue}};
                debug "Sending to pool " . $pool;
                $pool->add($data);
                my $rec = 0;
                while (!$rec){
                    $rec = kill 'ALRM', $pool->{pid};
                }
            }
        }
        
        my @ready = $select->can_read(.001);
        foreach my $ready (@ready){
            my $data = <$ready>;
            my $t = thaw $data;
            my $id = $t->{id};
            push @{$self->{pool}}, delete $POOL->{$id};
            $self->{parent}->($t->{data});
        }
        
        last if !@ready && !$data && !keys $POOL;
    }
    
    $self->destroy();
}

sub run_once {
    my $self = shift;
    my $timeout = shift || 0;
    local $/ = '[END]';
    my $data = $self->{queue}->[0];
    if ($data) {
        my $pool = $self->_getFreePool();
        if ($pool) {
            my $data = shift @{$self->{queue}};
            debug "Sending to pool " . $pool;
            $pool->add($data);
        }
    }
    
    my @ready = $select->can_read($timeout);
    foreach my $ready (@ready){
        $select->remove($ready);
        my $data = <$ready>;
        my $t = thaw $data;
        my $id = $t->{id};
        push @{$self->{pool}}, delete $POOL->{$id};
        $self->{parent}->($t->{data});
    }
}

sub DESTROY {
    shift->destroy();
}

sub destroy {
    my $self = shift;
    
    my $pool = $self->{pool};
    for (@{$pool}){
        #close $_->{child};
    }
    
    foreach my $pid (@{ $self->{children} }){
        kill 'KILL', $pid;
    }
}

package Rum::Forker::Pool; {
    use strict;
    use warnings;
    use IO::Handle;
    use Socket;
    use Storable qw(freeze thaw store_fd fd_retrieve);
    use Data::Dumper;
    sub new {
        my ($class,$id) = @_;
        
        open(my $fh, '>>', undef) or die $!;
        $fh->autoflush(1);
        
        my $self = bless {
            id => $id,
            fh => $fh
        }, __PACKAGE__;
        
        return $self;
    }
    
    sub add {
        my $self = shift;
        my $data = shift;
        my $t = {
            data => $data
        };
        
        my $fh = $self->{fh};
        store_fd $t, $fh;
    }
}

1;

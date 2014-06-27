use lib 'E:\R\lib';
use Rum;
use Test::More;
use Data::Dumper;
my $Readable = Require('stream')->Readable;
print Dumper $Readable;
my $ms = MyStream->new();
my $results = [];
$ms->on('readable', sub {
    my $chunk;
    while (defined ($chunk = $ms->read())) {
        push @{$results},$chunk->toString();
    }
});

my $expect = [ 'first chunksecond to last chunk', 'last chunk' ];
process->on('exit', sub {
    is($ms->{_chunks}, -1);
    is_deeply($results, $expect);
    done_testing(2);
});

package MyStream; {
    use Rum;
    use base 'Rum::Stream::Readable';
    sub new {
        my ($class,$options) = @_;
        my $this = bless{}, $class;
        $this->{_chunks} = 3;
        $this->SUPER::new($options);
        return $this;
    }
    
    sub _read {
        my ($this,$n) = @_;
        my $switch = $this->{_chunks}--;
        if ($switch == 0) {
            return $this->push(undef);
        } elsif ($switch == 1){
            return setTimeout( sub {
                $this->push('last chunk');
            }, 100);
        } elsif ($switch == 2){
            return $this->push('second to last chunk');
        } elsif ($switch == 3){
            return process->nextTick( sub {
                $this->push('first chunk');
            });
        }
        
        die "?";
    }
    
}

1;

use Rum;
use Test::More;

{
    my $m = MyWritable->new( sub {
        my ($isBuffer, $type, $enc) = @_;
        ok($isBuffer);
        is($type, 'Rum::Buffer');
        is($enc, 'buffer');
        #diag('ok - decoded string is decoded');
    }, { decodeStrings => 1 });
    
    #print Dumper $m;
    $m->write('some-text', 'utf8');
    $m->end();
};

{
    my $m = MyWritable->new( sub {
        my ($isBuffer, $type, $enc) = @_;
        ok(!$isBuffer);
        ok(!$type);
        is($enc, 'utf8');
        #diag('ok - un-decoded string is not decoded');
    }, { decodeStrings => 0 });
    
    $m->write('some-text', 'utf8');
    $m->end();
};

process->on('exit',sub{
    done_testing();
});

package MyWritable; {
    use Rum;
    use base 'Rum::Stream::Writable';
    sub new {
        my ($class, $fn, $options) = @_;
        my $this = bless {}, $class;
        $this->SUPER::new($options);
        $this->{fn} = $fn;
        return $this;
    }
    
    sub _write {
        my ($this, $chunk, $encoding, $callback) = @_;
        $this->{fn}->(Buffer->isBuffer($chunk), ref $chunk, $encoding);
        $callback->();
    }
}

1;

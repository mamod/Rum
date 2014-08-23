use lib '../../lib';
use Rum;

use Data::Dumper;
use Time::HiRes 'time';

my $common = Require('../common');
my $assert = Require('assert');
my $fork = Require('child_process')->{fork};
my $path = Require('path');
my $net = Require('net');
my $count = 12;

sub debug {
    print "\n";
    printf @_;
    #print "\n";
}

if (process->argv->[2] && process->argv->[2] eq 'child') {
    my $needEnd = [];
    my $id = process->argv->[3];

    process->on('message', sub {
        my ($this, $m, $socket) = @_;
        
        if (!$socket || ref $socket !~ /Rum/) { return };
        
        debug('[%d] got socket %s', $id, $m);
        #will call .end('end') or .write('write');
        if ($m eq 'end') {
            $socket->end($m);
        } elsif ($m eq 'write'){
            $socket->write($m);
        } else {
            die;
        }
        
        $socket->resume();
        $socket->on('data', sub {
            debug('[%d] socket.data %s', $id, $m);
        });
        
        $socket->on('end', sub {
            debug('[%d] socket.end %s', $id, $m);
        });
        
        #store the unfinished socket
        if ( $m eq 'write') {
            push @{$needEnd}, $socket;
        }
        
        $socket->on('close', sub {
            my ($this, $had_error) = @_;
            debug('[%d] socket.close', $id, $had_error, $m);
        });
        
        $socket->on('finish', sub {
            debug('[%d] socket finished %s', $id, $m);
        });
    });
    
    process->on('message', sub {
        my ($this, $m) = @_;
        if ($m ne 'close') { return };
        debug('[%d] got close message', $id);
        my $i = 0;
        foreach my $endMe (@{$needEnd}){
            debug('[%d] ending %d/%d', $id, $i, scalar @{$needEnd});
            $endMe->end('end');
            $i++;
        }
        
        #needEnd.forEach(function(endMe, i) {
        #    console.error('[%d] ending %d/%d', id, i, needEnd.length);
        #    endMe.end('end');
        #});
    });
    
    process->on('disconnect', sub {
        debug('[%d] process disconnect, ending', $id);
        my $i = 0;
        foreach my $endMe (@{$needEnd}){
            debug('[%d] ending %d/%d', $id, $i, scalar @{$needEnd});
            $endMe->end('end');
            $i++;
        }
        
        #needEnd.forEach(function(endMe, i) {
        #    console.error('[%d] ending %d/%d', id, i, needEnd.length);
        #    endMe.end('end');
        #});
    });

} else {
    
    use Test::More;
    
    plan skip_all => "BUGGY TEST";
    
    my $child1 = $fork->(process->argv->[1], ['child', '1']);
    my $child2 = $fork->(process->argv->[1], ['child', '2']);
    my $child3 = $fork->(process->argv->[1], ['child', '3']);

    my $server = $net->createServer();
    
    my $connected = 0;
    my $closed = 0;
    
    $server->on('connection', sub {
        my ($this, $socket) = @_;
        my $switch = $connected % 6;
        
        if ($switch == 0) {
            $child1->send('end', $socket, { track => 0 });
        } elsif ($switch == 1){
            $child1->send('write', $socket, { track => 1 });
        } elsif ($switch == 2){
            $child2->send('end', $socket, { track => 1 });
        } elsif ($switch == 3){
            $child2->send('write', $socket, { track => 0 });
        } elsif ($switch == 4){
            $child3->send('end', $socket, { track => 0 });
        } elsif ($switch == 5){
            $child3->send('write', $socket, { track => 0 });
        }
        
        $connected += 1;
        
        $socket->once('close', sub {
            debug('[m] socket closed, total %d', ++$closed);
        });
        
        if ( $connected == $count) {
            closeServer();
        }
    });

    my $disconnected = 0;
  
    $server->on('listening', sub {
        
        my $j = $count;
        my $client;
        while ($j--) {
            $client = $net->connect($common->{PORT}, '127.0.0.1');
            
            $client->on('error', sub {
                #This can happen if we kill the child too early.
                #The client should still get a close event afterwards.
                debug('[m] CLIENT: error event');
            });
            
            $client->on('close', sub {
                debug('[m] CLIENT: close event');
                $disconnected += 1;
            });
            
            #XXX This resume() should be unnecessary.
            #a stream high water mark should be enough to keep
            #consuming the input.
            $client->resume();
        }
    });

    my $closeEmitted = 0;
  
    $server->on('close', sub {
        debug('[m] server close');
        $closeEmitted = 1;
        
        debug('[m] killing child processes');
        $child1->kill();
        $child2->kill();
        
        #FIXME: last child will emit error IPC channel already closed?!
        #$child3->kill();
    });
    
    $server->listen($common->{PORT}, '127.0.0.1');
    
    my $timeElasped = 0;
    sub closeServer {
        debug('[m] closeServer');
        my $startTime = time() * 1000;
        $server->on('close', sub {
            debug('[m] emit(close)');
            #die Dumper $startTime;
            $timeElasped = int((time() * 1000) - $startTime);
        });
        
        debug('[m] calling server.close');
        $server->close();
        
        setTimeout( sub {
            $assert->ok(!$closeEmitted);
            debug('[m] sending close to children');
            $child1->send('close');
            $child2->send('close');
            $child3->disconnect();
        }, 300);
    };

    process->on('exit', sub {
        is($disconnected, $count);
        $assert->equal($connected, $count);
        $assert->ok($closeEmitted);
        $assert->ok($timeElasped >= 190 && $timeElasped <= 1000,
              'timeElasped was not between 190 and 1000 ms ' . $timeElasped);
        
        #print "1..1\n";
        print "ok 1\n";
        Test::More::done_testing(1);
    });
}

1;

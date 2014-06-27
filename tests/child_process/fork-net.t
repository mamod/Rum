use lib '../../lib';
use Rum;
use Test::More;
use Data::Dumper;
my $common = Require('../common');
my $assert = Require('assert');
my $fork = Require('child_process')->{fork};
my $path = Require('path');
my $net = Require('net');



sub debug {
    process->stderr->write($_[0] . "\n");
}

if (process->argv->[2] && process->argv->[2] eq 'child') {
    
    my $serverScope;
    
    my $onServer; $onServer = sub {
        my ($this, $msg, $server) = @_;
        
        if ($msg->{what} ne 'server') { return };
        process->removeListener('message', $onServer);
        
        $serverScope = $server;
        
        $server->on('connection', sub {
            my ($this,$socket) = @_;
            debug('CHILD: got connection');
            process->send({what => 'connection'});
            $socket->destroy();
        });
        
        #start making connection from parent
        debug('CHILD: server listening');
        process->send({what => 'listening'});
    };
    
    process->on('message', $onServer);
    
    my $onClose; $onClose = sub {
        my ($this,$msg) = @_;
        if ($msg->{what} ne 'close') { return };
        process->removeListener('message', $onClose);
        
        $serverScope->on('close', sub {
            process->send({what => 'close'});
        });
        $serverScope->close();
    };
    
    process->on('message', $onClose);
    
    my $onSocket; $onSocket = sub {
        my ($this, $msg, $socket) = @_;
        if ($msg->{what} ne 'socket') { return };
        process->removeListener('message', $onSocket);
        $socket->end('echo');
        debug('CHILD: got socket');
    };
    
    process->on('message', $onSocket);
    process->send({what => 'ready'});
    
} else {
    
    my $child = $fork->(process->argv->[1], ['child']);
    $child->on('exit', sub {
        debug('CHILD: died');
    });
    
    #send net.Server to child and test by connecting
    my $testServer = sub {
        my $callback = shift;
        
        #create server and send it to child
        my $server = $net->createServer();
        
        #destroy server execute callback when done
        my $progress = ProgressTracker->new(2, sub {
            $server->on('close', sub {
                debug('PARENT: server closed');
                $child->send({what => 'close'});
            });
            $server->close();
        },'progress');
        
        #we expect 10 connections and close events
        my $connections = ProgressTracker->new(10, sub {
            $progress->done();
        },'connection');
        
        my $closed = ProgressTracker->new(10, sub {
            $progress->done();
        },'closed');
        
        $server->on('connection', sub {
            my ($this, $socket) = @_;
            debug('PARENT: got connection');
            $socket->destroy();
            $connections->done();
        });
        
        $server->on('listening', sub {
            debug('PARENT: server listening');
            $child->send({what => 'server'}, $server);
        });
        $server->listen($common->{PORT});
        
        #handle client messages
        my $messageHandlers; $messageHandlers = sub {
            my $this = shift;
            my $msg = shift;
            if ($msg->{what} eq 'listening') {
                #make connections
                for (my $i = 0; $i < 10; $i++) {
                    my $socket = $net->connect($common->{PORT}, sub {
                        debug('CLIENT: connected');
                    });
                    $socket->on('close', sub {
                        $closed->done();
                        debug('CLIENT: closed');
                    });
                }
            } elsif ($msg->{what} eq 'connection') {
                #child got connection
                $connections->done();
            } elsif ($msg->{what} eq 'close') {
                $child->removeListener('message', $messageHandlers);
                $callback->();
            }
        };
        
        $child->on('message', $messageHandlers);
    };

    #send net.Socket to child
    my $testSocket = sub {
        my $callback = shift;
        #create a new server and connect to it,
        #but the socket will be handled by the child
        my $server = $net->createServer();
        $server->on('connection', sub {
            my ($this, $socket) = @_;
            $socket->on('close', sub {
                debug('CLIENT: socket closed');
            });
            $child->send({what => 'socket'}, $socket);
        });
        
        $server->on('close', sub {
            debug('PARENT: server closed');
            $callback->();
        });
        
        #don't listen on the same port, because SmartOS sometimes says
        #that the server's fd is closed, but it still cannot listen
        #on the same port again.
        
        #An isolated test for this would be lovely, but for now, this
        #will have to do.
        $server->listen($common->{PORT} + 1, sub {
            debug('testSocket, listening');
            my $connect = $net->connect($common->{PORT} + 1);
            my $store = '';
            $connect->on('data', sub {
                my ($this, $chunk) = @_;
                $store .= $chunk->toString;
                debug('CLIENT: got data');
            });
            
            $connect->on('close', sub {
                debug('CLIENT: closed');
                is($store, 'echo');
                $server->close();
            });
        });
    };

    #create server and send it to child
    my $serverSuccess = 0;
    my $socketSuccess = 0;
    
    my $onReady; $onReady = sub {
        my $this = shift;
        my $msg = shift;
        if ($msg->{what} ne 'ready') { return };
        $child->removeListener('message', $onReady);
        
        $testServer->( sub {
            $serverSuccess = 1;
            
            $testSocket->( sub {
                $socketSuccess = 1;
                #print STDERR Dumper $child;
                #kill -9, $child->{pid} or die $!;
                #$child->kill();
            });
        });
        
    };
    
    $child->on('message', $onReady);
    
    process->on('exit', sub {
        ok($serverSuccess);
        ok($socketSuccess);
        done_testing();
    });
}


#progress tracker
package ProgressTracker; {
    use Data::Dumper;
    sub new {
        my ($class, $missing, $callback, $name) = @_;
        return bless {
            missing => $missing,
            callback => $callback,
            name => $name
        }, $class;
    }
    
    sub done {
        my $this = shift;
        #print STDERR Dumper $this;
        $this->{missing} -= 1;
        $this->check();
    }
    
    sub check {
        my $this = shift;
        if ($this->{missing} <= 0) { $this->{callback}->() }
    }
    
}

1;

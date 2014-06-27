package Rum::Loop::Fs;
use strict;
use warnings;
use Rum::Loop::Queue;
use Fcntl qw(O_RDONLY O_WRONLY O_RDWR);
use Data::Dumper;
use base qw/Exporter/;
our @EXPORT = qw (
    fs_open
    fs_fstat
    fs_ftruncate
    fs_read
);

sub INIt {
    my ($req,$loop,$cb,$type) = @_;
    $loop->req_init($req, 'FS');
    $req->{fs_type} = 'FS_' . $type;
    $req->{result} = 0;
    $req->{loop} = $loop;
    $req->{new_path} = undef;
    $req->{cb} = $cb;
}

sub POST {
    my ($loop,$req,$cb) = @_;
    if ($cb) {
        $loop->work_submit($req, 'Rum::Loop::Fs::fs_work', 'Rum::Loop::Fs::fs_done');
        return 0;
    } else {
        fs_work($req);
        fs_done($req, 0);
        return $req->{result};
    }
}

sub fs_open {
    my ($loop,$req,$path,$mode,$flags,$cb) = @_;
    
    if (!defined $flags) {
        $flags = 0666;
    } elsif (ref $flags eq 'CODE') {
        $cb = $flags;
        $flags = 0666;
    }
    
    INIt($req,$loop,$cb,'OPEN');
    $req->{flags} = $flags;
    $req->{mode} = $mode;
    $req->{path} = $path;
    POST($loop,$req,$cb);
}

sub fs_read {
    my ($loop,$req,$file,$buf,$len,$off,$cb) = @_;
    
    #allow off as an optional value
    if (!defined $off) {
        $off = 0;
    } elsif (ref $off eq 'CODE'){
        $cb = $off;
        $off = 0;
    }
    
    INIt($req,$loop,$cb,'READ');
    if (ref $file) {
        $req->{file} = fileno $file;
        $req->{fh} = $file;
    } else {
        $req->{file} = $file;
    }
    
    $req->{buf} = $_[3];
    $req->{len} = $len;
    $req->{off} = $off;
    POST($loop,$req,$cb);
}

sub fs_fstat {
    my ($loop,$file,$cb) = @_;
    my $req = newReq();
    INIt($req,$loop,$cb,'FSTAT');
    $req->{file} = $file;
    POST($loop,$req,$cb);
}

sub fs_ftruncate {
    my ($loop,$req,$file,$off,$cb) = @_;
    INIt($req,$loop,$cb,'FTRUNCATE');
    $req->{file} = $file;
    $req->{off} = $off;
    POST($loop,$req,$cb);
}


my $action = {
    'FS_FTRUNCATE' => sub {
        my $req = shift;
        return truncate $req->{file}, $req->{off};
    },
    'FS_READ' => sub {
        my $req = shift;
        my $fh = $req->{fh} || do {
            my $fd = $req->{file};
            open my $FH, "<&=$fd" or die $!;
            $FH;
        };
        
        if ($req->{len} == -1) {
            $req->{len} = -s $fh;
        }
        
        if (!$req->{off} || $req->{off} < 0) {
            return sysread($fh, $req->{buf}, $req->{len});
        } else {
            return sysread($fh, $req->{buf}, $req->{len}, $req->{off});
        }
    },
    'FS_OPEN' => sub {
        my $req = shift;
        sysopen($req->{fh}, $req->{path}, $req->{mode},$req->{flags});
        return fileno $req->{fh};
    }
};

sub fs_work {
    my $req = shift;
    my $type = $req->{fs_type};
    #print $type . "\n";
    die "$type is not a defined action" if !$action->{$type};
    my $r = $action->{$type}->($req);
    if (!$r) {
        $req->{result} = $!;
    } else {
        $req->{result} = $r;
    }
}

sub fs_done {
    my $req = shift;
    $req->{loop}->req_unregister($req);
    if ($req->{cb}) {
        $req->{cb}->($req);
    }
    undef $req;
}

1;

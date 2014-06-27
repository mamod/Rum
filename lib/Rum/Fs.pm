package Rum::Fs;
use strict;
use warnings;
use Rum;
use Rum::Utils;
use Rum::IO;
use Rum::Path;
use Rum::Buffer;
use Rum::Fs::ReadStream;
use Rum::Fs::WriteStream;
use Fcntl ':mode';
use FileHandle;
use Carp;
use Data::Dumper;

module->{exports} = __PACKAGE__;
my $pathModule = 'Rum::Path';
my $Utils = Rum::Utils->new();

my $HANDLES = {};

sub _makePath {
    my $path = shift;
    if (!$path) {
        Carp::croak 'path required';
    }
    if (!$Utils->isString($path)) {
        Carp::croak "path must be a string";
    }
    return $pathModule->resolve($path);
}

sub _modeNum {
    my ($m, $def) = @_;
    if ($Utils->isNumber($m)) {
        return $m;
    }
    if (!$def) {
        Carp::croak "mode must be a number";
    }
    return _modeNum($def);
}

sub rethrow {
    return sub {
        my ($err) = @_;
        Carp::croak $err if $err;
    }
}

sub maybeCallback {
    my ($cb) = @_;
    return ref $cb eq 'CODE' ? $cb : rethrow();
}

sub GET_OFFSET {
    $Utils->isNumber($_[0]) ? $_[0] : -1;
}

my $switch = {
    'r' => O_RDONLY,
    #rs => O_RDONLY | O_SYNC,
    'r+' => O_RDWR,
    #'rs+' => O_RDWR | O_SYNC,
    'w' => O_TRUNC | O_CREAT | O_WRONLY,
    'wx' => '',
    'xw' => O_TRUNC | O_CREAT | O_WRONLY | O_EXCL,
    'w+' => O_TRUNC | O_CREAT | O_RDWR,
    'wx+' => '',
    'xw+' => O_TRUNC | O_CREAT | O_RDWR | O_EXCL,
    'a' => O_APPEND | O_CREAT | O_WRONLY,
    'ax' => '', # fall through
    'xa' => O_APPEND | O_CREAT | O_WRONLY | O_EXCL,
    'a+' => O_APPEND | O_CREAT | O_RDWR,
    'ax+' => '',# fall through
    'xa+' => O_APPEND | O_CREAT | O_RDWR | O_EXCL
};

sub stringToFlags {
    my ($flag) = @_;

    if ($Utils->isNumber($flag)) {
        return $flag;
    }

    $flag = $switch->{$flag};
    Carp::croak ('Unknown file open flag: ' . $_[0]) if !defined $flag;
    return $flag;
}

sub fh { shift;$HANDLES->{$_[0]} }
#=========================================================================
# exists
#=========================================================================
sub exists {
    my ($self, $path, $callback) = @_;
    #if (!nullCheck(path, cb)) return;
    my $cb = sub {
        my ($err, $stats) = @_;
        $callback->($err ? 0 : 1) if $callback;
    };
    
    $self->stat($pathModule->resolve($path), $cb);
}

sub existsSync {
    my ($self,$path) = @_;
    try {
        #nullCheck(path);
        $self->stat($pathModule->resolve($path));
        return 1;
    } catch {
        return 0;
    };
}

#=========================================================================
# stat
#=========================================================================
sub statSync {&stat}
sub stat {
    my ($self,$path,$callback) = @_;
    my $rpath = _makePath($path);
    if ($callback && ref $callback eq 'CODE') {
        my $cb = sub {
            my ($err,$data) = @_;
            my @stat = stat $rpath or return $callback->($!);
            $callback->(undef, Rum::Fs::Stats->new($rpath,@stat));
        };
        process->nextTick($cb);
        return;
    }
    
    my @stat = stat $rpath or Carp::croak $! . " " . $rpath;
    return Rum::Fs::Stats->new($rpath,@stat);
}

#=========================================================================
# fstat
#=========================================================================
sub fstatSync { &fstat }
sub fstat {
    my ($self,$fd,$callback) = @_;
    if (@_ < 1 || !$Utils->isNumber($_[1])) {
        Carp::croak('Bad argument');
    }
    my $fh = $HANDLES->{$fd};
    if ($callback && ref $callback eq 'CODE') {
        my $cb = sub {
            my ($err,$data) = @_;
            return $callback->('bad file descriptor') if !$fh;
            my @stat = CORE::stat $fh or return $callback->($!);
            $callback->(undef, Rum::Fs::Stats->new($fh,@stat));
        };
        process->nextTick($cb);
        return;
    }
    
    if (!$fh) {
        Carp::croak('bad file descriptor');
    }
    
    my @stat = CORE::stat $fh or Carp::croak $!;
    return Rum::Fs::Stats->new($fh,@stat);
}

#=========================================================================
# truncate
#=========================================================================
sub truncate {
    my ($self, $path, $len, $callback) = @_;
    if ($Utils->isNumber($path)) {
        #legacy
        return $self->ftruncate($path, $len, $callback);
    }
    
    if (ref $len eq 'CODE') {
        $callback = $len;
        $len = 0;
    } elsif (!defined $len) {
        $len = 0;
    }
    
    $callback = maybeCallback($callback);
    $self->open($path, 'w', sub {
        my ($er, $fd) = @_;
        return $callback->($er) if ($er);
        Rum::IO::ADD ('truncate', $fd, sub {
            CORE::truncate($HANDLES->{$fd}, $len) or return $callback->($!);
            ##only close if it was a path
            $self->close($fd, sub {
                my ($er2) = @_;
                $callback->($er || $er2);
            });
        });
    });
}

sub ftruncate {
    my ($self, $fd, $len, $callback) = @_;
    if (ref $len eq 'CODE') {
        $callback = $len;
        $len = 0;
    } elsif (!defined $len) {
        $len = 0;
    }
    
    Rum::IO::ADD ('truncate', $fd, sub{
        my $fh = $HANDLES->{$fd};
        if (!$fh) {
            return $callback->('bad file descriptor');
        }
        
        CORE::truncate($fh, $len) or return $callback->($!);
        return $callback->(undef);
    });
}

sub truncateSync {
    my ($self, $path, $len) = @_;
    if ($Utils->isNumber($path)) {
        #legacy
        return $self->ftruncateSync($path, $len);
    }
    
    if (!defined $len) {
        $len = 0;
    }
    
    #allow error to be thrown, but still close fd.
    my $fd = $self->openSync($path, 'w');
    my $ret;
    try {
        $ret = $self->ftruncateSync($fd, $len);
    } finally {
        $self->closeSync($fd);
    };
    
    return $ret;
}

sub ftruncateSync {
    my ($self, $fd, $len) = @_;
    if ( !defined $len ) {
        $len = 0;
    }
    my $fh = $HANDLES->{$fd};
    if (!$fh) {
        Carp::croak('bad file descriptor');
    }
    return CORE::truncate($fh, $len);
}

#=========================================================================
# open
#=========================================================================
sub openSync {&Rum::Fs::open}
sub open {
    my ($self,$path, $flags, $mode) = @_;
    my $callback = pop @_;
    $mode = _modeNum($mode, 438);
    my $flag = stringToFlags($flags);
    my $rpath = _makePath($path);
    
    if (ref $callback eq 'CODE') {
        Rum::IO::ADD( 'open', $path, sub {
            sysopen my $fh, $rpath, $flag, $mode or return $callback->($!);
            my $fd = fileno $fh;
            $HANDLES->{$fd} = $fh;
            $callback->(undef,$fd);
        });
        return;
    }
    
    sysopen(my $fh, $rpath, $flag, $mode) or croak $! . '';
    my $fd = fileno $fh;
    $HANDLES->{$fd} = $fh;
    return $fd;
}

#=========================================================================
# close
#=========================================================================
sub closeSync {&Rum::Fs::close}
sub close {
    my ($self, $fd, $callback) = @_;
    if ($callback && ref $callback eq 'CODE') {
        Rum::IO::ADD( 'close', $fd, sub{
            my $fh = delete $HANDLES->{$fd};
            if (!$fh) {
                return $callback->("bad file descriptor");
            }
            
            close $fh or $callback->($!);
            $callback->(undef);
        });
        return;
    }
    
    my $fh = delete $HANDLES->{$fd};
    if (!$fh) {
        Carp::croak "bad file descriptor";
    }
    
    close $fh or Carp::croak $!;
    return 0;
}

#=========================================================================
# readFile
#=========================================================================
sub readFile{
    my ($self, $path, $options, $callback_) = @_;
    my $callback = pop @_;

    if (ref $options eq 'CODE' || !$options) {
        $options = { encoding => undef, flag => 'r' };
    } elsif (!ref $options) {
        $options = { encoding => $options, flag => 'r' };
    } elsif ( ref $options ne 'HASH' ) {
        Carp::croak('Bad arguments');
    }

    my $encoding = $options->{encoding};
    #assertEncoding(encoding);

    #first, stat the file, so we know the size.
    my $size;
    my $buffer; # single buffer with file data
    my $buffers; # list for when size is unknown
    my $pos = 0;
    my $fd;

    my $flag = $options->{flag} || 'r';
    my ($read,$afterRead,$close);
    
    $read = sub {
        if ($size == 0) {
            $buffer = Rum::Buffer->new(8192);
            $self->read($fd, $buffer, 0, 8192, -1, $afterRead);
        } else {
            $self->read($fd, $buffer, $pos, $size - $pos, -1, $afterRead);
        }
    };
    
    $afterRead = sub {
        my ($er, $bytesRead) = @_;
        if ($er) {
            return $self->close($fd, sub {
                my ($er2) = @_;
                return $callback->($er);
            });
        }
        
        if ($bytesRead == 0) {
            return $close->();
        }
        
        $pos += $bytesRead;
        if ($size != 0) {
            return $close->() if ($pos == $size);
            $read->();
        } else {
            #unknown size, just read until we don't get bytes.
            #buffers.push($buffer->slice(0, $bytesRead));
            push @{$buffers}, $buffer->slice(0, $bytesRead);
            $read->();
        }
    };
    
    $close = sub {
        $self->close($fd, sub {
            my ($er) = @_;
            if ($size == 0) {
                # collected the data into the buffers list.
                $buffer = Rum::Buffer->concat($buffers, $pos);
            } elsif ($pos < $size) {
                $buffer = $buffer->slice(0, $pos);
            }
            
            $buffer = $buffer->toString($encoding) if $encoding;
            return $callback->($er, $buffer);
        });
    };
    
    $self->open($path, $flag, 438, sub {
        my ($er, $fd_) = @_;
        return $callback->($er) if $er;
        $fd = $fd_;
        $self->fstat($fd, sub {
            my ($er, $st) = @_;
            return $callback->($er) if $er;
            $size = $st->{size};
            if ($size == 0) {
                #the kernel lies about many files.
                #Go ahead and try to read some bytes.
                $buffers = [];
                return $read->();
            }
            $buffer = Rum::Buffer->new($size);
            return $read->();
        });
    });
}

sub readFileSync {
    my ($self, $path, $options) = @_;
    if (!$options) {
        $options = { encoding => undef, flag => 'r' };
    } elsif ( $Utils->isString($options) ) {
        $options = { encoding => $options, flag => 'r' };
    } elsif ( ref $options ne 'HASH' ) {
        Carp::croak('Bad arguments');
    }

    my $encoding = $options->{encoding};
    #assertEncoding(encoding);

    my $flag = $options->{flag} || 'r';
    my $fd = $self->openSync($path, $flag, 438);
    
    my $size = 0;
    my $threw = 1;
    try {
        $size = $self->fstatSync($fd)->{size};
        $threw = 0;
    } finally {
        $self->closeSync($fd) if ($threw);
    }

    my $pos = 0;
    my $buffer; # single buffer with file data
    my $buffers; # list for when size is unknown
    
    if ($size == 0) {
        $buffers = [];
    } else {
        $buffer = Rum::Buffer->new($size);
    }

    my $done = 0;
    while (!$done) {
        my $threw = 1;
        my $bytesRead = 0;
        try {
            if ($size != 0) {
                $bytesRead = $self->readSync($fd, $buffer, $pos, $size - $pos);
            } else {
                #the kernel lies about many files.
                #Go ahead and try to read some bytes.
                $buffer = Rum::Buffer->new(8192);
                $bytesRead = $self->readSync($fd, $buffer, 0, 8192);
                if ($bytesRead) {
                    push @{$buffers}, $buffer->slice(0, $bytesRead);
                }
            }
            $threw = 0;
        } finally {
            $self->closeSync($fd) if ($threw);
        };
        
        $pos += $bytesRead;
        $done = ($bytesRead == 0) || ($size != 0 && $pos >= $size);
    }

    $self->closeSync($fd) if $self->fh($fd);

    if ($size == 0) {
        #data was collected into the buffers list.
        $buffer = Rum::Buffer->concat($buffers, $pos);
    } elsif ($pos < $size) {
        $buffer = $buffer->slice(0, $pos);
    }
    
    $buffer = $buffer->toString($encoding) if ($encoding);
    return $buffer;
}

#=========================================================================
# write methods
#=========================================================================
sub _writeBuffer {
    
    my ($fd, $buf, $off, $len, $pos, $cb) = @_;
    
    #my $pos = GET_OFFSET($position);
    if ($Utils->isBuffer($buf)) {
        my $buffer_length = $buf->length;
        return Carp::croak("offset out of bounds") if ($off > $buffer_length);
        return Carp::croak("length out of bounds") if $len > $buffer_length;
        return Carp::croak("off + len overflow") if $off + $len < $off;
        return Carp::croak("off + len > buffer->length") if $off + $len > $buffer_length;
    }
    
    if ($cb && ref $cb eq 'CODE') {
        Rum::IO::ADD('write', $fd, sub{
            my $fh = $HANDLES->{$fd} or return $cb->("bad file descriptor $fd");
            sysseek $fh,$pos,0 or return $cb->($!) if defined $pos;
            my $ret = syswrite $fh, $buf->{buf}, $len, $off or return $cb->($!);
            return $cb->(undef,$ret,$buf);
        });
        return;
    }
    
    ##async
    my $fh = $HANDLES->{$fd} or Carp::croak("bad file descriptor $fd");
    sysseek $fh,$pos,0 or Carp::croak($!) if defined $pos;
    my $ret = syswrite $fh, $buf->{buf}, $len, $off or Carp::croak($!);
    return $ret;
}

sub _writeString {
    my ($fd, $str, $position, $encoding) = @_;
    my $cb = pop @_;
    my $off = 0;
    #assertEncoding($encoding);
    my $bufEm = Rum::Buffer->new($str,$encoding);
    my $len = $bufEm->length;
    my $ret = _writeBuffer($fd, $bufEm, $off, $len, $position,$cb);
    undef $bufEm; #clear
    return $ret;
}

sub write {
    my ($self, $fd, $buffer, $offset, $length, $position, $callback) = @_;
    if ($Utils->isBuffer($buffer)) {
        #if no position is passed then assume undef
        if (ref $position eq 'CODE') {
            $callback = $position;
            $position = undef;
        }
        
        $callback = maybeCallback($callback);
        return _writeBuffer($fd, $buffer, $offset, $length, $position, $callback);
    }

    $buffer .= '' if $Utils->isString($buffer);
    if (ref $position ne 'CODE') {
        if (ref $offset eq 'CODE') {
            $position = $offset;
            $offset = undef;
        } else {
            $position = $length;
        }
        $length = 'utf8';
    }
    
    $callback = maybeCallback($position);
    $position = sub {
        my ($err, $written) = @_;
        #retain reference to string in case it's external
        $callback->($err, $written || 0, $buffer);
    };
    return _writeString($fd, $buffer, $offset, $length, $position);
}


sub writeSync {
    my ($self, $fd, $buffer, $offset, $length, $position) = @_;
    if ( $Utils->isBuffer($buffer) ) {
        if (!defined $position) {
            $position = undef;
        }
        
        return _writeBuffer($fd, $buffer, $offset, $length, $position);
    }
    
    if ( !$Utils->isString($buffer) ) {
        $buffer = "$buffer";
    }
    
    if (!defined $offset) {
        $offset = undef;
    }
    
    return _writeString($fd, $buffer, $offset, $length, $position);
}

sub writeAll {
    my ($self, $fd, $buffer, $offset, $length, $position, $callback) = @_;
    $callback = maybeCallback(pop @_);

    #write(fd, buffer, offset, length, position, callback)
    $self->write($fd, $buffer, $offset, $length, $position, sub {
        my ($writeErr, $written) = @_;
        if ($writeErr) {
            $self->close($fd, sub {
                $callback->($writeErr) if $callback;
            });
        } else {
            if ($written == $length) {
                $self->close($fd, $callback);
            } else {
                $offset += $written;
                $length -= $written;
                $position += $written;
                $self->writeAll($fd, $buffer, $offset, $length, $position, $callback);
            }
        }
    });
}

sub writeFileSync {
    my ($self, $path, $data, $options) = @_;
    if (!$options) {
        $options = { encoding => 'utf8', mode => 438, flag => 'w' };
    } elsif ($Utils->isString($options)) {
        $options = { encoding => $options, mode => 438, flag => 'w' };
    } elsif (ref $options ne 'HASH') {
        Carp::croak('Bad arguments');
    }
    
    #assertEncoding($options->{encoding});
    my $flag = $options->{flag} || 'w';
    my $fd = $self->openSync($path, $flag, $options->{mode} );
    if (!$Utils->isBuffer($data)) {
        $data = Rum::Buffer->new('' . $data, $options->{encoding} || 'utf8');
    }
    
    my $written = 0;
    my $length = $data->length;
    my $position = $flag =~ /a/ ? undef : 0;
    
    try {
        while ($written < $length) {
            $written += $self->writeSync($fd, $data, $written, $length - $written, $position);
            $position += $written;
        }
    } finally {
        $self->closeSync($fd);
    };
}

sub writeFile {
    my ($self, $path, $data, $options, $callback) = @_;
    $callback = maybeCallback(pop @_);
    if ( ref $options eq 'CODE' || !$options ) {
        $options = { encoding => 'utf8', mode => 438, flag => 'w' };
    } elsif ( $Utils->isString($options) ) {
        $options = { encoding => $options, mode => 438, flag => 'w' };
    } elsif ( ref $options ne 'HASH' ) {
        Carp::croak('Bad arguments');
    }

    #assertEncoding($options->{encoding});

    my $flag = $options->{flag} || 'w';
    $self->open($path, $flag, $options->{mode}, sub {
        my ($openErr, $fd) = @_;
        if ($openErr) {
            $callback->($openErr) if $callback;
        } else {
            my $buffer = $Utils->isBuffer($data)
            ? $data
            : Rum::Buffer->new('' . $data, $options->{encoding} || 'utf8');
            
            my $position = $flag =~ /a/ ? undef : 0;
            $self->writeAll($fd, $buffer, 0, $buffer->length, $position, $callback);
        }
    });
}

#=========================================================================
# append
#=========================================================================
sub appendFile {
    my ($self, $path, $data, $options, $callback_) = @_;
    my $callback = maybeCallback(pop @_);

    if (ref $options eq 'CODE' || !$options) {
        $options = { encoding => 'utf8', mode => 438, flag => 'a' };
    } elsif ($Utils->isString($options)) {
        $options = { encoding => $options, mode => 438, flag => 'a' };
    } elsif (ref $options ne 'HASH') {
        Carp::croak('Bad arguments');
    }

    if (!$options->{flag}) {
        $options->{flag} = 'a';
        #$options = $Utils->extend({ flag => 'a' }, $options);
    }
    $self->writeFile($path, $data, $options, $callback);
}

sub appendFileSync {
    my ($self, $path, $data, $options) = @_;
    if (!$options) {
        $options = { encoding => 'utf8', mode => 438, flag => 'a' };
    } elsif ($Utils->isString($options)) {
        $options = { encoding => $options, mode => 438, flag => 'a' };
    } elsif (ref $options ne 'HASH') {
        Carp::croak('Bad arguments');
    }
  
    if (!$options->{flag}) {
        $options->{flag} = 'a';
    }
    
    $self->writeFileSync($path, $data, $options);
}

#=========================================================================
# read & readSync
#=========================================================================
sub _read {
    my ($fd, $buffer, $off, $len, $pos, $cb) = @_;
    if (@_ < 2 || !$Utils->isNumber($_[0]) ) {
        Carp::croak('THROW_BAD_ARGS');
    }

    if (!$Utils->isBuffer($buffer) ) {
        Carp::croak("Second argument needs to be a buffer");
    }

    my $buffer_length = $buffer->length;

    if ($off >= $buffer_length) {
        Carp::croak("Offset is out of bounds");
    }

    if ($off + $len > $buffer_length) {
        Carp::croak("Length extends beyond buffer");
    }
    
    #$pos = GET_OFFSET($pos);
    
    ##TODO : ERROR checking for sysread
    if ($cb && ref $cb eq 'CODE') {
        Rum::IO::ADD ('read' , $fd, sub {
            my $fh = $HANDLES->{$fd};
            return $cb->('bad file descriptor') if !$fh;
            sysseek $fh,$pos,0 if defined $pos;
            my $bytesread = sysread $fh, $buffer->{buf}, $len, $off;
            return $cb->(undef,$bytesread,$buffer);
        });
        return;
    }
    
    my $fh = $HANDLES->{$fd};
    Carp::croak 'bad file descriptor' if !$fh;
    sysseek $fh,$pos,0 if defined $pos;
    my $bytesread = sysread $fh, $buffer->{buf}, $len, $off
    or Carp::croak($!);
    return $bytesread;
}

sub read {
    my ($self, $fd, $buffer, $offset, $length, $position, $callback) = @_;
    if (ref $buffer ne 'Rum::Buffer') {
        #legacy string interface (fd, length, position, encoding, callback)
        my $cb = $_[5];
        my $encoding = $_[4];
        #assertEncoding(encoding);
        $position = $_[3];
        $length = $_[2];
        $buffer = Rum::Buffer->new($length);
        $offset = 0;
        $callback = sub {
            my ($err, $bytesRead) = @_;
            return if (!$cb);
            my $str = ($bytesRead > 0) ? $buffer->toString($encoding, 0, $bytesRead) : '';
            $cb->($err, $str, $bytesRead);
        };
    }
    
    ##FIXME : to be removed
    my $wrapper = sub {
        my ($err, $bytesRead) = @_;
        $callback && $callback->($err, $bytesRead || 0, $buffer);
    };
    
    _read($fd, $buffer, $offset, $length, $position, $wrapper);
}

sub readSync {
    my ($self, $fd, $buffer, $offset, $length, $position) = @_;
    $position ||= 0;
    my $legacy = 0;
    my $encoding;
    if (ref $buffer ne 'Rum::Buffer') {
        #legacy string interface (fd, length, position, encoding, callback)
        $legacy = 1;
        $encoding = $_[4];
        #assertEncoding($encoding);
        $position = $_[3];
        $length = $_[2];
        $buffer = Rum::Buffer->new($length);
        $offset = 0;
    }

    my $r = _read($fd, $buffer, $offset, $length, $position);
    if (!$legacy) {
        return $r;
    }

    my $str = ($r > 0) ? $buffer->toString($encoding, 0, $r) : '';
    return [$str, $r];
}


#

*ReadStream = \&createReadStream;
sub createReadStream {
    my ($self, $path, $options) = @_;
    return Rum::Fs::ReadStream->new($path, $options);
}

*WriteStream = \&createWriteStream;
sub createWriteStream {
    my ($self, $path, $options) = @_;
    return Rum::Fs::WriteStream->new($path, $options);
}

#=========================================================================
# Rum::Fs::Stats
#=========================================================================
package Rum::Fs::Stats; {
    use strict;
    use warnings;
    use Fcntl ':mode';
    
    sub new {
        my $class = shift;
        my $path = shift;
        my @stats = @_;
        return bless {
            _path => $path,
            dev => $stats[0],
            ino => $stats[1],
            mode => $stats[2],
            nlink => $stats[3],
            uid => $stats[4],
            gid => $stats[5],
            rdev => $stats[6],
            size => $stats[7],
            blksize => $stats[11],
            blocks => $stats[12],
            atime => $stats[8],
            mtime => $stats[9],
            ctime => $stats[10]
        }, $class;
    }

    sub _checkModeProperty {
        my ($this,$property) = @_;
        return (($this->{mode} & S_IFMT) == $property);
    }

    sub isDirectory {
        return shift->_checkModeProperty(S_IFDIR);
    }

    sub isFile {
        return shift->_checkModeProperty(S_IFREG);
    }

    sub isBlockDevice {
        return shift->_checkModeProperty(S_IFBLK);
    }

    sub isCharacterDevice {
        return shift->_checkModeProperty(S_IFCHR);
    }

    sub isSymbolicLink {
        return shift->_checkModeProperty(S_IFLNK);
    }

    sub isFIFO {
        return shift->_checkModeProperty(S_IFIFO);
    }

    sub isSocket {
        return shift->_checkModeProperty(S_IFSOCK);
    }
}

1;

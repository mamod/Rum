package Rum::Module;
use strict;
use warnings;
use Data::Dumper;

my $NativeModules = {
    'path'           => 'Rum::Lib::Path',
    'util'           => 'Rum::Lib::Utils',
    'events'         => 'Rum::Lib::Events',
    'buffer'         => 'Rum::Buffer',
    'domain'         => 'Rum::Domain',
    'stream'         => 'Rum::Lib::Stream',
    'assert'         => 'Rum::Lib::Assert',
    'test'           => 'Rum::Lib::Test',
    'fs'             => 'Rum::Fs',
    'os'             => 'Rum::Lib::OS',
    'buffer'         => 'Rum::Lib::Buffer',
    'net'            => 'Rum::Net',
    'tty'            => 'Rum::Lib::TTY',
    'string_decoder' => 'Rum::Lib::StringDecoder',
    'child_process'  => 'Rum::Lib::ChildProcess',
    'repl'           => 'Rum::Lib::REPL',
    'dns'            => 'Rum::DNS',
    ##Http
    'http'           => 'Rum::HTTP',
    '_http_incoming' => 'Rum::HTTP::Incoming',
    '_http_common'   => 'Rum::HTTP::Common',
    '_http_agent'    => 'Rum::HTTP::Agent',
    '_http_client'   => 'Rum::HTTP::Client',
    '_http_outgoing' => 'Rum::HTTP::Outgoing',
    '_http_server'   => 'Rum::HTTP::Server'
};

my $EX = {};
my $modulePaths = [];
my $cache = {};
my $NativeCache = {};

$EX->{'.json'} = sub {};
$EX->{'.t'} = sub {
    my ($self,$filename) = @_;
    $self->compile($filename);
};

sub NativeRequire {
    my ($id) = @_;
    return $NativeCache->{$id}->{exports} if $NativeCache->{$id};
    my $filename = $NativeModules->{$id};
    my $module = $NativeCache->{$id} = bless {}, __PACKAGE__;
    $module->{exports} = bless {}, 'Rum::Module::Load';
    my $ret = eval qq{
        {
            no warnings 'redefine';
            sub Rum::exports  { \$module->{exports} }
            sub Rum::module {\$module}
        }
        require $filename;
        1;
    };
    die $@ if $@;
    bless $module->{exports}, 'Rum::Module::Load' if ref $module->{exports} eq 'HASH';
    return $module->{exports};
}

sub Require {
    my ($id,$parent) = @_;
    
    return  NativeRequire($id) if $NativeModules->{$id};
    my $module = __PACKAGE__->new($id,$parent);
    return $module->load();
}

sub new {
    my $class = shift;
    my $id = shift;
    my $parent  = shift;
    my $self = bless {
        exports => {},
        id => $id,
        parent => $parent || undef,
        children => [],
        filename => undef,
    },$class;
    bless $self->{exports}, 'Rum::Module::Load';
    if ($parent && $parent->{children}) {
        push @{ $parent->{children} }, $self;
    }
    return $self;
}

sub load {
    my $self = shift;
    $self->resolve();
    my $filename = $self->{filename} || '.';
    my $dirname = $self->{dirname};
    my $parent = $self->{parent};
    my $path = Require('path');
    if ($filename && $cache->{$filename}){
        return $cache->{$filename}->{exports};
    }
    
    $cache->{$filename} = $self;
    my $extension = $path->extname($filename) || '.pl';
    if ( my $processor = $EX->{$extension} ) {
        $processor->($self,$filename);
    } elsif ($extension eq '.pl'){
        $self->compile($filename);
    }
    
    return $self->{exports};
}

sub compile {
    my $self = shift;
    my $filename = shift;
    my $dirname = $self->{dirname};
    my $_package = $filename;
    $_package =~ s/([^A-Za-z0-9_])/sprintf("_%2x", unpack("C", $1))/eg;
    eval qq{
        package Rum::SandBox::$_package; {
            {
                no warnings 'redefine';
                sub Rum::__dirname {\$dirname}
                sub Rum::__filename {\$filename}
                sub Rum::Require { Rum::Module::Require(shift,\$self) }
                sub Rum::exports  { \$self->{exports} }
                sub Rum::module {\$self}
            }
            require '$filename';
        }
    };
    die $@ if $@;
    bless $self->{exports}, 'Rum::Module::Load' if ref $self->{exports} eq 'HASH';
}

sub resolve {
    my $self = shift;
    my $request = $self->{id};
    my $path = Require('path');
    my $basename = $path->basename($request);
    my $ext = $path->extname($basename);
    my $start = substr $request, 0,1;
    my $searchpath;
    my $searchPaths = [];
    if ($start eq '.' || $start eq '/') {
        $searchPaths = [$request];
    } else {
        if (defined $self->{parent}){
            $searchPaths = constructPaths($self->{parent}->{dirname},$request);
        } else {
            $searchPaths = [$request];
        }
    }
    
    #will return matched extension
    $self->tryFiles($searchPaths,$ext);
    if (!$self->{parent}){
        Rum::process()->{mainModule} = $self;
        $self->{id} = '.';
    }
}

sub constructPaths {
    my ($parent,$req) = @_;
    my $path = Require('path');
    my $x = 1;
    my $sep = $path->sep;
    my @paths = split /\Q$sep\E/,$parent;
    my @b = ();
    for (my $i = scalar @paths; $i > 0; $i--){
        my @cpath = @paths[0 .. $i-1];
        push @b, ((join $sep, @cpath) . $sep . 'modules' . $sep . $req)
    }
    return \@b;
}

sub tryFiles {
    my ($self,$paths,$ext) = @_;
    my $extinsions = $ext ?
        [''] :
        ['','.pl','.json','/index.pl','/index.json'];
    
    my @tried = ();
    my $path = Require('path');
    foreach my $p (@$paths){
        foreach my $extend ( @$extinsions ){    
            my $tryFile = $path->resolve( $self->{parent} ?
            $self->{parent}->{dirname} :
            Rum::process()->cwd(), $p . $extend );
            push @tried, $tryFile;
            if (-f $tryFile){
                $self->{id} = $self->{filename} = $tryFile;
                $self->{dirname} = $path->dirname($tryFile);
                return $ext ? $ext : $extend;
            }
        }
    }
    
    die 'Cant Find Module [ ' . $self->{id}
    . " ] in the following locations\n"
    . (join "\n", @tried) . "\n\n";
}

package Rum::Module::Load; {
    use Carp;
    use strict;
    our $AUTOLOAD;
    sub AUTOLOAD {
        my $self = shift;
        my $caller = caller;
        my ($method) = ($AUTOLOAD =~ /([^:']+$)/);
        return if $method eq 'DESTROY';
        my $called = $self->{$method};
        if (!$called) {
            Carp::croak "[ $method ] is not exported -> " . $caller;
        }
        if ( ref $called eq 'CODE' ) {
            my $ret = $called->(@_);
            return $ret;
        }
        return $called;
    }
}

1;

use 5.010001;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Rum',
    VERSION_FROM      => 'lib/Rum.pm',
    PREREQ_PM         => {},
    ABSTRACT_FROM     => 'lib/Rum.pm', #retrieve abstract from module
    AUTHOR            => 'Mamod A. Mehyar <mamod.mehyar@gmail.com>',
    LICENSE           => 'perl',
    test              => {TESTS => join( ' ', (glob( 't/*.t'), glob('t/*/*.t')))},
);

use strict;
use warnings;
use Rum::Timers;
use Test::More;

my $intervalThis;
my $timeoutThis;
my $intervalArgsThis;
my $timeoutArgsThis;

my $intervalHandler = setInterval( sub {
    my $this = shift;
    clearInterval($this);
    $intervalThis = $this;
});

my $intervalArgsHandler = setInterval( sub {
    my $this = shift;
    clearInterval($this);
    $intervalArgsThis = $this;
}, 0, "args ...");

my $timeoutHandler = setTimeout( sub {
    my $this = shift;
    $timeoutThis = $this;
});

my $timeoutArgsHandler = setTimeout( sub {
  my $this = shift;
  $timeoutArgsThis = $this;
}, 0, "args ...");

start_timers();

is_deeply($intervalThis, $intervalHandler);
is_deeply($intervalArgsThis, $intervalArgsHandler);
is_deeply($timeoutThis, $timeoutHandler);
is_deeply($timeoutArgsThis, $timeoutArgsHandler);

done_testing(4);

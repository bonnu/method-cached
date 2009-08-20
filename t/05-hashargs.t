#!/usr/bin/env perl

use strict;
use Test::More 'no_plan';

{
    package Dummy::HashArgs;

    use Method::Cached;

    sub echo :Cached(0, HASH) {
        my (%args) = @_;
        sprintf 'param1-%s param2-%s %s',
            (defined $args{param1} ? $args{param1} : q{}),
            (defined $args{param2} ? $args{param2} : q{}),
            rand;
    }

    package Dummy::HashKeys;

    use Method::Cached;

    sub echo :Cached(0, HASH_KEYS(qw/foo bar baz/)) {
        my (%args) = @_;
        sprintf 'foo-%s bar-%s baz-%s %s',
            (defined $args{foo} ? $args{foo} : q{}),
            (defined $args{bar} ? $args{bar} : q{}),
            (defined $args{baz} ? $args{baz} : q{}),
            rand;
    }
}

# Dummy::HashArgs
{
    my $param1 = rand;
    my $param2 = rand;

    my %params = (
        param1 => $param1,
        param2 => $param2,
    );

    my $value1 = Dummy::HashArgs::echo(%params);
    my $value2 = Dummy::HashArgs::echo(%params);

    delete $params{param2};

    my $value3 = Dummy::HashArgs::echo(%params);

    $params{param2} = undef;

    my $value4 = Dummy::HashArgs::echo(%params);

    $params{param2} = $param2;

    my $value5 = Dummy::HashArgs::echo(%params);

    $params{param3} = 1;

    my $value6 = Dummy::HashArgs::echo(%params);

    is   $value1, $value2;
    isnt $value1, $value3;
    isnt $value1, $value4;
    is   $value1, $value5;
    isnt $value1, $value6;
}

# Dummy::HashKeys
{
    my @foo = (foo => rand);
    my @bar = (bar => rand);
    my @baz = (baz => rand);
    
    my $value1 = Dummy::HashKeys::echo(@foo, @bar, @baz, qux  => rand);
    my $value2 = Dummy::HashKeys::echo(@baz, @foo, @bar, quux => rand);
    my $value3 = Dummy::HashKeys::echo(@foo, bar => 2, @baz);
    my $value4 = Dummy::HashKeys::echo(bar => 3, @foo, @baz);
    my $value5 = Dummy::HashKeys::echo(@foo, @bar);
    my $value6 = Dummy::HashKeys::echo();
    my $value7 = Dummy::HashKeys::echo(@baz, @bar, @foo);

    is   $value1, $value2, $value2;
    isnt $value1, $value3, $value3;
    isnt $value1, $value4, $value4;
    isnt $value1, $value5, $value5;
    isnt $value1, $value6, $value6;
    is   $value1, $value7, $value7;
}

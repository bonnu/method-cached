#!/usr/bin/env perl

use strict;
use Test::More tests => 7;

{
    use Method::Cached;
    is_deeply(
        Method::Cached->default_domain,
        {
            storage_class => 'Cache::FastMmap',
        }
    );
}

{
    my $apps_1 = {
        storage_class => 'Cache::FastMmap',
        storage_args  => [
            share_file     => '/tmp/apps1_cache.bin',
            unlink_on_exit => 1,
        ],
        key_rule      => 'HASH',
    };
    my $apps_2 = {
        storage_class => 'Cache::FastMmap',
        storage_args  => [
            share_file     => '/tmp/apps2_cache.bin',
            unlink_on_exit => 1,
        ],
        key_rule      => [qw/PER_OBJECT HASH/],
    };
    Method::Cached->import(-domains => {
        apps_1 => $apps_1,
        apps_2 => $apps_2,
    });
    is_deeply(Method::Cached->get_domain('apps_1'), $apps_1);
    is_deeply(Method::Cached->get_domain('apps_2'), $apps_2);
}

{
    eval { Method::Cached->import(-domains => []) };
    like $@, qr/^-domains option should be a hash reference/;
}

{
    eval { Method::Cached->import(-default => 0) };
    like $@, qr/^-default option should be a hash reference/;
}

{
    eval { Method::Cached->import(-default => { storage_class => 'B' }) };
    like $@, qr/^storage_class needs the following methods:/;
}

{
    eval { Method::Cached->import(-default => { storage_class => 'Dummy' . time }) };
    like $@, qr/^Can't load module:/;
}

package Method::Cached::Manager;

use strict;
use warnings;
use Carp qw/croak confess/;
use UNIVERSAL::require;
use Method::Cached::KeyRule;

my %DOMAIN;
my %METHOD;
my $DEFAULT_DOMAIN = { class  => 'Cache::FastMmap' };
my %ATTR_PARSER    = ( Cached => \&_parse_attr_args );

sub import {
    my ($class, %args) = @_;
    if (exists $args{-domains} && defined $args{-domains}) {
        my $domains = $args{-domains};
        ref $domains eq 'HASH'
            || confess '-domains option should be a hash reference';
        $class->set_domain(%{ $domains });
    }
    if (exists $args{-default} && defined $args{-default}) {
        my $default = $args{-default};
        ref $default eq 'HASH'
            || confess '-default option should be a hash reference';
        $class->default_domain($default);
    }
    else {
        _inspect_storage_class($DEFAULT_DOMAIN->{class});
    }
}

sub set_domain {
    my $class = shift;
    set_domain_setting(@_);
}

sub get_domain {
    my $class = shift;
    get_domain_setting(@_);
}

sub default_domain {
    my ($class, $args) = @_;
    if ($args) {
        exists $args->{key_rule} && delete $args->{key_rule};
        $DEFAULT_DOMAIN = {
            %{ $DEFAULT_DOMAIN },
            %{ $args },
        };
        _inspect_storage_class($DEFAULT_DOMAIN->{class});
    }
    return $DEFAULT_DOMAIN;
}

sub get_key {
    my ($class, $name) = splice @_, 0, 2;
    my $method = get_method_setting($name);
    my $domain = get_domain_setting($method->{domain});
    my $rule   = $method->{key_rule} || $domain->{key_rule};
    return Method::Cached::KeyRule::regularize($rule, $name, [ @_ ]);
}

sub get_context_key {
    my $warray = splice @_, 2, 1;
    return get_key(@_) . _context_suffix($warray ? 1 : 0);
}

sub get_instance {
    my ($class, $domain) = @_;
    $domain->{instance} && return $domain->{instance};
    my $st_class = $domain->{class} || croak 'class is necessary';
    my $st_args  = $domain->{args}  || undef;
    $domain->{instance} = $st_class->new(@{ $st_args || [] });
}

sub delete {
    my ($class, $name) = splice @_, 0, 2;
    unless (exists_method_setting($name)) {
        if ($name =~ /^(.*)::[^:]*$/) {
            my $package = $1;
            $package->require || confess "Can't load module: $package";
        }
    }
    if (exists_method_setting($name)) {
        my $method  = get_method_setting($name);
        my $domain  = get_domain_setting($method->{domain});
        my $cache   = $class->get_instance($domain);
        my $key     = $class->get_key($name, @_);
        my $del_sub = $cache->can('delete') || $cache->can('clear');
        my @suffix  = _context_suffix();
        $del_sub->($cache, $key . $_) for @suffix;
    }
}

sub set_method_setting {
    my ($name, $attr, @args) = @_;
    my $parser_sub = _get_attr_parser($attr);
    my ($domain, $expires, $key_rule, %extend) = $parser_sub->(@args);
    $METHOD{$name} = {
        domain   => $domain,
        expires  => $expires,
        key_rule => $key_rule,
        %extend,
    };
}

sub get_method_setting {
    my ($name) = @_;
    return $METHOD{$name};
}

sub exists_method_setting {
    my ($name) = @_;
    return exists $METHOD{$name};
}

sub set_domain_setting {
    my (%args) = @_;
    for my $name (keys %args) {
        my $args = $args{$name};
        if (exists $DOMAIN{$name}) {
            warn 'This domain has already been defined: ' . $name;
            next;
        }
        $DOMAIN{$name} = $args;
        _inspect_storage_class($DOMAIN{$name}->{class});
    }
}

sub get_domain_setting {
    my ($domain) = @_;
    return exists $DOMAIN{$domain} ? $DOMAIN{$domain} : default_domain();
}

sub exists_domain {
    my ($domain) = @_;
    return exists $DOMAIN{$domain};
}

sub set_attr_parser {
    my ($attr, $parser) = @_;
    $ATTR_PARSER{$attr} = $parser;
}

sub _get_attr_parser {
    my $attr = shift;
    return $ATTR_PARSER{$attr} || \&_parse_attr_args;
}

sub _parse_attr_args {
    my $domain   = q{};
    my $expires  = 0;
    my $key_rule = undef;
    if (0 < @_) {
        if (! defined $_[0] || $_[0] !~ /^?\d+$/) {
            $domain = shift;
        }
    }
    $domain ||= q{};
    if (0 < @_) {
        $expires  = ($_[0] =~ /^\d+$/) ? shift @_ : confess
            'The first argument or the second argument should be a numeric value.';
        $key_rule = shift if 0 < @_;
    }
    return ($domain, $expires, $key_rule);
}

sub _context_suffix {
    my @context = qw/ :s :l /;
    defined $_[0] ? $context[$_[0]] : @context;
}

sub _inspect_storage_class {
    my $any_class = shift;
    my $invalid;
    $any_class->require || confess "Can't load module: $any_class";
    $any_class->can($_) || $invalid++ for qw/new set get/;
    $any_class->can('delete') || $any_class->can('remove') || $invalid++;
    $invalid &&
        croak 'storage-class needs the following methods: new, set, get, delete or remove';
}

1;

__END__

=head1 NAME

Method::Cached::Manager - Storage for cache used in Method::Cached is managed

=head1 SYNOPSIS

=head2 SETTING OF CACHED DOMAIN

In beginning logic or the start-up script:

 use Method::Cached::Manager
     -default => { class => 'Cache::FastMmap' },
     -domains => {
         'some-namespace' => {
             class => 'Cache::Memcached::Fast',
             args  => [
                 {
                     # Parameter of constructor of class that uses it for cashe
                     servers => [ '192.168.254.2:11211', '192.168.254.3:11211' ],
                     ...
                 },
             ],
         },
     },
 ;

=head1 DESCRIPTION

Storage for cache used in Method::Cached is managed.

Cache used by default when not specifying it and
cache that can be used by specifying the domain can be defined.

This setting is shared on memory management in perl.

=head1 METHODS

=over 4

=item B<import ('-default' =E<gt> {}, '-domains' =E<gt> {})>

=item B<delete ( METHOD_FQN, METHOD_ARGS [, ...] )>

When it is defined in the package as follows:

 package Foo::Bar;
 use Method::Cached;
 sub foo_bar :Cached(60 * 30, [HASH]) { ... }

This method is used as follows:

 Foo::Bar::foo_bar(args1 => 1, args2 => 2);

To erase a cache of this method:

 Method::Cached::Manager->delete(
     'Foo::Bar::foo_bar',       # fqn
     (args1 => 1, args2 => 2),  # hash-args
 );

=back

=head1 FUNCTIONS

=over 4

=back

=head1 AUTHOR

Satoshi Ohkubo E<lt>s.ohkubo@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

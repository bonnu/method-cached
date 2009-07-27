package Method::Cached;

use strict;
use warnings;
use Attribute::Handlers;
use B qw/svref_2object/;
use Carp qw/croak confess/;
use UNIVERSAL::require;
use Method::Cached::KeyRule;

our $VERSION = '0.045_1';

my %_DOMAINS;
my $_DEFAULT_DOMAIN = { storage_class => 'Cache::FastMmap' };
my %_METHOD_INFO;
my %_PREPARE_INFO;

sub import {
    my ($class, %args) = @_;
    if ($class eq __PACKAGE__) {
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
            _inspect_storage_class($_DEFAULT_DOMAIN->{storage_class});
        }
        unless (exists $args{-inherit} && $args{-inherit} eq 'no') {
            my $caller = caller 0;
            if ($caller ne 'main' && ! $caller->isa(__PACKAGE__)) {
                no strict 'refs';
                unshift @{$caller . '::ISA'}, __PACKAGE__;
            }
        }
    }
    else {
        $class->_apply_cached;
    }
}

sub UNIVERSAL::Cached :ATTR(CODE,BEGIN,INIT) {
    my ($package, $symbol, $code, $attr, $args, $phase, $file, $line) = @_;
    $args = [ $args || () ] if ref $args ne 'ARRAY';
    my $name;
    if ($phase eq 'BEGIN') {
        my $name = $package->_scan_symbol_name($file, $line) || return;
        _prepare_info($package, $name, $code);
        _method_info($package, $name, $code, _parse_attr_args(@{$args}));
    }
    if ($phase eq 'INIT') {
        my $name = $package . '::' . *{$symbol}{NAME};
        _method_info($package, $name, $code, _parse_attr_args(@{$args}));
        _defined_code($name) || _replace_cached($name);
    }
}

sub delete {
    my ($class, $name) = splice @_, 0, 2;
    unless (exists $_METHOD_INFO{$name}) {
        if ($name =~ /^(.*)::([^:]*)$/) {
            my ($package, $method) = ($1, $2);
            $package->require || confess "Can't load module: $package";
        }
    }
    if (exists $_METHOD_INFO{$name}) {
        my $info    = $_METHOD_INFO{$name};
        my $dname   = $info->{domain};
        my $domain  = $_DOMAINS{$dname} ? $_DOMAINS{$dname} : $_DEFAULT_DOMAIN;
        my $rule    = $info->{key_rule} || $domain->{key_rule};
        my $key     = Method::Cached::KeyRule::regularize($rule, $info->{name}, [ @_ ]);
        my $storage = _storage($domain);
        my $dmethod = $storage->can('delete') || $storage->can('clear');
        $dmethod->($storage, $key . $_) for qw/ :l :s /;
    }
}

sub default_domain {
    my ($class, $args) = @_;
    if ($args) {
        exists $args->{key_rule} && delete $args->{key_rule};
        $_DEFAULT_DOMAIN = {
            %{ $_DEFAULT_DOMAIN },
            %{ $args },
        };
        _inspect_storage_class($_DEFAULT_DOMAIN->{storage_class});
    }
    return $_DEFAULT_DOMAIN;
}

sub set_domain {
    my ($class, %args) = @_;
    for my $name (keys %args) {
        my $args = $args{$name};
        if (exists $_DOMAINS{$name}) {
            warn 'This domain has already been defined: ' . $name;
            next;
        }
        $_DOMAINS{$name} = $args;
        _inspect_storage_class($_DOMAINS{$name}->{storage_class});
    }
}

sub get_domain {
    my ($class, $dname) = @_;
    return $_DOMAINS{$dname};
}

sub _scan_symbol_name {
    my ($package, $file, $line) = @_;
    no strict 'refs';
    for (values %{$package . '::'}) {
        (my $symbol = $_) =~ s/^\*//;
        my $gv = svref_2object(\*{$symbol});
        next if ref $gv ne 'B::GV';
        return $symbol if $line == $gv->LINE && $file eq $gv->FILE;
    }
    return;
}

sub _apply_cached {
    my $class = shift;
    my $prof  = exists $_PREPARE_INFO{$class} ? $_PREPARE_INFO{$class} : ();
    return unless $prof;
    for my $name (keys %{$prof}) {
        _replace_cached($name);
    }
}

sub _replace_cached {
    my $name = shift;
    no strict 'refs';
    no warnings;
    *{$name} = sub { unshift @_, $_METHOD_INFO{$name}, wantarray; goto &_wrapper };
}

sub _parse_attr_args {
    my $dname    = q{};
    my $expires  = 0;
    my $key_rule = undef;
    if (0 < @_) {
        if ((! defined $_[0]) || ($_[0] !~ /^?\d+$/)) {
            $dname = shift;
        }
    }
    $dname ||= q{};
    if (0 < @_) {
        $expires  = ($_[0] =~ /^\d+$/) ? shift @_ : confess
            'The first argument or the second argument should be a numeric value.';
        $key_rule = shift if 0 < @_;
    }
    return ($dname, $expires, $key_rule);
}

sub _prepare_info {
    my ($package, $name, $code) = @_;
    my $profile = $_PREPARE_INFO{$package} ||= {};
    $profile->{$name} = $code;
}

sub _defined_code {
    my $name = shift;
    my $info = $_METHOD_INFO{$name} || return;
    my $prof = $_PREPARE_INFO{$info->{package}} || return;
    $prof->{$name} eq $info->{code};
}

sub _method_info {
    my ($package, $name, $code, $dname, $expires, $key_rule) = @_;
    $_METHOD_INFO{$name} = {
        'package'  => $package,
        'name'     => $name,
        'code'     => $code,
        'domain'   => $dname,
        'expires'  => $expires,
        'key_rule' => $key_rule,
    };
}

sub _storage {
    my $domain = shift;
    $domain->{_storage_instance} && return $domain->{_storage_instance};
    my $st_class = $domain->{storage_class} || croak 'storage_class is necessary';
    my $st_args  = $domain->{storage_args}  || undef;
    $domain->{_storage_instance} = $st_class->new(@{ $st_args || [] });
}

sub _inspect_storage_class {
    my $any_class = shift;
    my $invalid;
    $any_class->require || confess "Can't load module: $any_class";
    $any_class->can($_) || $invalid++ for qw/new set get/;
    $any_class->can('delete') || $any_class->can('remove') || $invalid++;
    $invalid && croak
        'storage_class needs the following methods: new, set, get, delete or remove';
}

sub _wrapper {
    my ($info, $warray) = splice @_, 0, 2;
    my $dname   = $info->{domain};
    my $domain  = $_DOMAINS{$dname} ? $_DOMAINS{$dname} : $_DEFAULT_DOMAIN;
    my $rule    = $info->{key_rule} || $domain->{key_rule};
    my $key     = Method::Cached::KeyRule::regularize($rule, $info->{name}, [ @_ ]);
    my $key_af  = $key . ($warray ? ':l' : ':s');
    my $storage = _storage($domain);
    my $ret     = $storage->get($key_af);
    unless ($ret) {
        $ret = [ $warray ? $info->{code}->(@_) : scalar $info->{code}->(@_) ];
        $storage->set($key_af, $ret, $info->{expires} || 0);
    }
    return $warray ? @{ $ret } : $ret->[0];
}

1;

__END__

=head1 NAME

Method::Cached - The return value of the method is cached to your storage

=head1 SYNOPSIS

  package Foo;
   
  use Method::Cached;
   
  sub message :Cached(5) { join ':', @_, time, rand }
  
  package main;
  use Perl6::Say;
  
  say Foo::message(1); # 1222333848
  sleep 1;
  say Foo::message(1); # 1222333848
  
  say Foo::message(5); # 1222333849

=head1 DESCRIPTION

Method::Cached offers the following mechanisms:

The return value of the method is stored in storage, and
the value stored when being execute it next time is returned.

=head2 SETTING OF CACHED DOMAIN

In beginning logic or the start-up script:

  use Method::Cached;
  
  Method::Cached->default_domain({
      storage_class => 'Cache::FastMmap',
  });
  
  Method::Cached->set_domain(
      'some-namespace' => {
          storage_class => 'Cache::Memcached::Fast',
          storage_args  => [
              {
                  # Parameter of constructor of class that uses it for cashe
                  servers => [ '192.168.254.2:11211', '192.168.254.3:11211' ],
                  ...
              },
          ],
      },
  );

=head2 DEFINITION OF METHODS

This function is mounting used as an attribute of the method. 

=over 4

=item B<:Cached ( DOMAIN_NAME, EXPIRES, [, KEY_RULE, ...] )>

The cached rule is defined specifying the domain name.

  sub message :Cached('some-namespace', 60 * 5, LIST) { ... }

=item B<:Cached ( EXPIRES, [, KEY_RULE, ...] )>

When the domain name is omitted, the domain of default is used.

  sub message :Cached(60 * 30, LIST) { ... }

=back

=head2 RULE TO GENERATE KEY

=over 4

=item B<LIST>

=item B<HASH>

=item B<SELF_SHIFT>

=item B<PER_OBJECT>

=back

=head2 OPTIONAL, RULE TO GENERATE KEY

  use Method::Cached;
  use Method::Cached::KeyRule::Serialize;

=over 4

=item B<SERIALIZE>

=item B<SELF_CODED>

=back

=head1 METHODS

=over 4

=item B<default_domain ($setting)>

=item B<set_domain (%domain_settings)>

=item B<get_domain ($domain_name)>

=back

=head1 AUTHOR

Satoshi Ohkubo E<lt>s.ohkubo@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

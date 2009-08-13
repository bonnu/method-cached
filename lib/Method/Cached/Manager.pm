package Method::Cached::Manager;

use strict;
use warnings;
use Carp qw/croak confess/;
use UNIVERSAL::require;

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

sub set_method_setting {
    my ($class, $name, $attr, @args) = @_;
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
    my ($class, $name) = @_;
    return $METHOD{$name};
}

sub exists_method_setting {
    my ($class, $name) = @_;
    return exists $METHOD{$name};
}

sub set_domain_setting {
    my ($class, %args) = @_;
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
    my ($class, $domain) = @_;
    return exists $DOMAIN{$domain} ? $DOMAIN{$domain} : $class->default_domain;
}

sub exists_domain {
    my ($class, $domain) = @_;
    return exists $DOMAIN{$domain};
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

sub get_instance {
    my ($class, $domain) = @_;
    $domain->{instance} && return $domain->{instance};
    my $st_class = $domain->{class} || croak 'class is necessary';
    my $st_args  = $domain->{args}  || undef;
    $domain->{instance} = $st_class->new(@{ $st_args || [] });
}

sub delete {
    my ($class, $name) = splice @_, 0, 2;
    unless ($class->exists_method_setting($name)) {
        if ($name =~ /^(.*)::[^:]*$/) {
            my $package = $1;
            $package->require || confess "Can't load module: $package";
        }
    }
    if ($class->exists_method_setting($name)) {
        my $method  = $class->get_method_setting($name);
        my $domain  = $class->get_domain_setting($method->{domain});
        my $rule    = $method->{key_rule} || $domain->{key_rule};
        my $key     = Method::Cached::KeyRule::regularize($rule, $name, [ @_ ]);
        my $cache   = $class->get_instance($domain);
        my $del_sub = $cache->can('delete') || $cache->can('clear');
        $del_sub->($cache, $key . $_) for qw/ :l :s /;
    }
}

{
    no warnings 'once';
    *set_domain = \&set_domain_setting;
    *get_domain = \&get_domain_setting;
}

sub set_attr_parser {
    my ($class, $attr, $parser) = @_;
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

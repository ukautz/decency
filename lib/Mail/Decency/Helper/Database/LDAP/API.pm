package Mail::Decency::Helper::Database::LDAP::API;

=head1 NAME

Mail::Decency::Helper::Database::LDAP::API

=head1 DESCRIPTION


=head1 SYNOPSIS

    my $m = Module->new;

=cut

use strict;
use warnings;
use Net::LDAPapi;

=head1 METHODS

=cut

sub new {
    my ( $class, $host, %attr ) = @_;
    
    my $scheme = $attr{ scheme };
    ( $host, my $port ) = split( /:/, $host );
    $port ||= 389;
    
    return bless {
        ldap => Net::LDAPapi->new( -url => $scheme. '://'. $host. ':'. $port )
    }, $class;
}

sub l {
    return shift->{ ldap };
}

sub bind {
    my ( $self, $user, undef, $password ) = @_;
    $self->l->bind_s( -dn => $user, -password => $password, -type => LDAP_AUTH_SIMPLE ); 
}

sub add {
    my ( $self, $dn, undef, $attrs_ref ) = @_;
    $self->l->add_s( $dn, $attrs_ref );
}

sub modify {
    my ( $self, $dn, undef, $attrs_ref ) = @_;
    $self->l->modify_s( $dn, $attrs_ref );
}

sub search {
    my ( $self, %attrs ) = @_;
    
    my $scope = $attrs{ scope } eq 'sub'
        ? LDAP_SCOPE_SUBTREE
        : ( $attrs{ scope } eq 'one'
            ? LDAP_SCOPE_ONELEVEL
            : LDAP_SCOPE_BASE
        )
    ;
    my $filter = ref( $attrs{ filter } ) ? $attrs{ filter }->as_string : $attrs{ filter };
    $self->l->msgfree;
    my $res_id = $self->l->search_s(
        $attrs{ base },
        $scope,
        $filter
    );
    
    print "SEARCH '$attrs{ scope }' $res_id $filter -> ". $self->l->count_entries. "\n";
    if ( $res_id < 0 ) {
        print "ERR: ". $self->l->errstring. ": ". $self->l->extramsg. "\n";
        die "ASD"
    }
    
    my $res = _SearchResult->new(
        ldap    => $self->l(),
        count   => $self->l->count_entries,
    );
    
    return $res;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This script belongs to Fortrabbit - Ulrich Kautz & Frank Laemmer GbR if not otherwise stated by the author.

=cut


package _SearchResult;

use Data::Dumper;
use constant {
    LDAP_REAL_PRECISION => 10_000
};

sub new {
    my ( $class, %attrs ) = @_;
    return bless \%attrs, $class;
}

sub pop_entry {
    my ( $self ) = @_;
    my $res = $self->{ ldap }->result_entry;
    unless ( $res ) {
        $self->{ ldap }->msgfree;
        return;
    }
    
    my $dn = $self->{ ldap }->get_dn( $res );
    return unless $dn;
    
    $self->{ entries } ||= $self->{ ldap }->get_all_entries;
    return unless defined $self->{ entries }->{ $dn };
    my $entry = _SearchResultEntry->new( %{ $self->{ entries }->{ $dn } } );;
    print "RETURN $self->{ entries }->{ $dn }, $entry / ". join( " / ", caller ). "\n";
    return $entry;
}

sub get_next_entry {
    my ( $self ) = @_;
    my $entry = $self->pop_entry();
    print "E $entry\n";
    return if ! $entry || $entry->get_value( 'ou' );
    my $map_ref = $self->{ ldap_key_map_reverse };
    my $data_types_ref = $self->{ data_types };
    
    return { map {
        my $v = $entry->get_value( $_ );
        my $k = defined $map_ref->{ $_ } ? $map_ref->{ $_ } : $_;
        my $t = defined $data_types_ref->{ $k } ? $data_types_ref->{ $k } : 'varchar';
        if ( $t eq 'real' ) {
            $v /= LDAP_REAL_PRECISION;
        }
        elsif ( $t ne 'integer' ) {
            $v = '' if $v eq '#';
        }
        ( $k => $v )
    } grep {
        defined $map_ref->{ $_ } || $_ eq 'cn'
    } $entry->attributes };
}

sub count {
    my ( $self ) = @_;
    return $self->{ count };
}

package _SearchResultEntry;

sub new {
    my ( $class, %attrs  ) = @_;
    return bless \%attrs, $class;
}

sub get_value {
    my ( $self, $k ) = @_;
    return defined $self->{ $k } ? $self->{ $k } : undef;
}

sub attributes {
    my ( $self ) = @_;
    return keys %$self;
}

1;

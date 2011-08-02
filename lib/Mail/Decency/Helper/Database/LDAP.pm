package Mail::Decency::Helper::Database::LDAP;

=head1 NAME

Mail::Decency::Helper::Database::LDAP - LDAP database


=head1 DESCRIPTION

Use LDAP database as source


=cut

use Mouse;
extends qw/
    Mail::Decency::Helper::Database
/;
use mro 'c3';
use version 0.74; our $VERSION = qv( "v0.2.0" );
use Data::Dumper;
use Net::LDAP;
use Net::LDAP::Util qw/
    escape_filter_value
    escape_dn_value
/;
use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED LDAP_CONTROL_SORTRESULT );
use Net::LDAP::Control::Paged;
use Net::LDAP::Control::Sort;
use Digest::SHA qw/ sha256_hex /;
use constant {
    LDAP_REAL_PRECISION => 10_000
};

=head1 ATTRIBUTES


=head2 db : Net::LDAP

Handle to ldap

=cut

has db => ( is => 'ro' );

=head2 base : Str

Base name for lookups, eg "dc=domain,dc=tld"

=cut

has base => ( is => 'ro', isa => 'Str', required => 1 );

=head2 host : Str

Either IP or hostname of the ldap server (NOT an URL)

=cut

has host => ( is => 'ro', isa => 'Str', required => 1 );

=head2 user

If set, user for bind . eg 'cn=admin,dc=domain,dc=tld'

=cut

has user => ( is => 'ro', isa => 'Str' );

=head2 password : Str

Password for bind

=cut

has password => ( is => 'ro', isa => 'Str' );

=head2 scheme : Str

Either ldap, ldaps or ldapi. Default: ldap

=cut

has scheme => ( is => 'ro', isa => 'Str', default => 'ldap', trigger => sub {
    my ( $self, $scheme ) = @_;
    DD::cop_it ref($self). "->scheme: has to be in 'ldap', 'ldaps', 'ldapi' but is '$scheme'"
        unless $scheme =~ /^ldap[si]?$/;
} );

=head2 config : HashRef

Additionalc configuration for setup new LDAP connection . See L<Net::LDAP/new>

=cut

has config => ( is => 'ro', isa => 'HashRef', default => sub {{}} );

=head2 ldap_key_map : HashRef

Contains mapping of schema -> table -> key to ldap key

=cut

has ldap_key_map => ( is => 'ro', isa => 'HashRef', default => sub {{}} );

=head2 ldap_key_map_reverse : HashRef

Contains mapping of ldap keys (eg decencyGreylistAddressIp) to output keys (eg ip)

=cut

has ldap_key_map_reverse => ( is => 'ro', isa => 'HashRef', default => sub {{}} );

has _use_net_ldap_api => ( is => 'rw', isa => 'Bool', default => 0 );

=head1 METHODS

=cut

sub BUILD {
    my ( $self ) = @_;
    
    if ( 0 && eval "use Net::LDAPapi; 1;" ) {
        $self->_use_net_ldap_api( 1 );
        $self->{ db } = Mail::Decency::Helper::Database::LDAP::API->new(
            $self->host,
            scheme  => $self->scheme,
            onerror => 'die',
            %{ $self->config }
        );
    }
    else {
        $self->{ db } = Net::LDAP->new(
            $self->host,
            scheme  => $self->scheme,
            onerror => 'die',
            %{ $self->config }
        );
    }
    
    # bind
    if ( $self->user && $self->password ) {
        eval {
            $self->db->bind( $self->user, password => $self->password )
        };
        if ( $@ ) {
            DD::cop_it "Could not connect to LDAP: $@\n";
        }
    }
    
    return $self;
}


=head2 disconnect

Close connection

=cut

sub disconnect {
    my ( $self ) = @_;
    $self->db->unbind if $self->db;
}


=head2 search_handle

Search in database for a key

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut

sub search_handle {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    
    my ( $handle, $meth ) = $self->search_read( $schema, $table, $search_ref, $args_ref );
    my @res = ();
    while( my $entry = $handle->$meth() ) {
        push @res, $entry;
    }
    
    return wantarray ? @res : \@res;
}


=head2 search_read

Returns read handle and read method name for massive read actions

=cut

sub search_read {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    
    # control (order, page) 
    my ( @control ) = ();
    
    # control: limit
    my $limit = $args_ref->{ offset } && $args_ref->{ limit }
        ? ( $args_ref->{ offset } + $args_ref->{ limit } )
        : ( $args_ref->{ limit } ? $args_ref->{ limit } : 0 )
    ;
    push @control, Net::LDAP::Control::Paged->new( size => $limit ) if $limit;
    
    # control: order
    if ( $args_ref->{ order } ) {
        my @order;
        foreach my $order_ref( @{ $args_ref->{ order } } ) {
            my $prefix = $order_ref->{ dir } eq 'asc' ? '-' : '';
            push @order, $prefix. $order_ref->{ col };
        }
        push @control, Net::LDAP::Control::Sort->new( order => join( ' ', @order ) ) if @order;
    }
    
    
    my $res = $self->db->search(
        base   => $self->_dn( $schema, $table ),
        scope  => 'one',
        filter => $self->update_query( $schema, $table, $search_ref ),
        ( @control ? ( control => \@control ) : () )
    );
    
    # if ( $args_ref->{ order } ) {
    #     my( $check ) = $res->control( LDAP_CONTROL_SORTRESULT );
    #     if ( $check ) {
    #         if ( $check->result ) {
    #             warn "Problem sorting ". $check->attr. ": ". $check->result. "\n";
    #         }
    #         else {
    #             warn "SORT OK\n";
    #         }
    #     }
    #     else {
    #         warn "Cannot sort\n";
    #     }
    # }
    
    bless $res, '_Net_LDAP_Search' unless ref( $res ) =~ /^_/;
    $res->{ ldap_key_map_reverse } = $self->ldap_key_map_reverse;
    $res->{ data_types } = $self->data_types( $schema, $table );
    
    if ( my $off = $args_ref->{ offset } ) {
        $res->pop_entry() while $off-- > 0;
    }
    
    return ( $res, 'get_next_entry' );
}


=head2 get_handle

Search in database for a key

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut

sub get_handle {
    my ( $self, $schema, $table, $search_ref, $no_lock ) = @_;
    my $cn = defined $search_ref->{ cn }
        ? $search_ref->{ cn }
        : eval { $self->_extract_unique( $schema, $table, $search_ref ) }
    ;
    my $ref;
    if ( $cn ) {
        my $search = eval { $self->db->search(
            base      => $self->_dn( $schema, $table, $cn ),
            scope     => 'base',
            sizelimit => 1,
            filter    => 'objectClass='. _name( $schema, $table )
        ) };
        if ( $search && $search->count == 1 ) {
            my $entry = $search->pop_entry;
            $ref = $self->_downgrade_entry( $schema, $table, $entry );
        }
    }
    else {
        ( $ref ) = $self->search_handle( $schema => $table => $search_ref, {
            no_lock => $no_lock,
        } );
        $ref = $self->_downgrade_entry( $schema, $table, $ref )
            if ref( $ref ) =~ /Net::LDAP::Entry/;
    }
    return $ref;
}


=head2 set_handle

Getter method for BerkeleyDB::*

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut

sub set_handle {
    my ( $self, $schema, $table, $search_ref, $data_ref, $args_ref ) = @_;
    $args_ref ||= {};
    $search_ref ||= {};
    $data_ref ||= {};
    
    #
    # UPDATE ALL
    #   none found -> no update
    #
    if ( $args_ref->{ update_all } ) {
        my $replace_ref = $self->_build_data( $schema, $table, $data_ref );
        my ( $handle, $meth ) = $self->search_read( $schema, $table, $search_ref );
        while( my $item = $handle->$meth() ) {
            $self->db->modify( $self->_dn( $schema, $table, $item->{ cn } ),
                replace => $replace_ref );
        }
    }
    
    #
    # UPSERTz
    #   update existing or create new
    #
    else {
        
        # get existing ..
        my $existing = $self->get_handle( $schema => $table => $search_ref );
        unless ( $existing ) {
            my $unique  = $self->_extract_unique( $schema, $table, $data_ref, $search_ref );
            my $add_ref = $self->_build_data( $schema, $table, $search_ref, $data_ref );
            $add_ref->{ objectClass } = [ escape_dn_value( _name( $schema, $table ) ) ];
            $self->_satisfy_data( $schema, $table, $add_ref );
            $add_ref->{ cn } = $unique;
            eval {
                $self->db->add(
                    $self->_dn( $schema, $table, $unique ), attrs => [ %$add_ref ] );
            };
            if ( $@ ) {
                $self->logger->error( "Failed set_handle (create) for $schema / $table / $unique: $@" );
                DD::cop_it "Failed set_handle (create) for $schema / $table / $unique: $@\n";
            }
        }
        
        else {
            my $replace_ref = $self->_build_data( $schema, $table, $data_ref );
            eval {
                $self->db->modify(
                    $self->_dn( $schema, $table, $existing->{ cn } ), replace => $replace_ref );
            };
            if ( $@ ) {
                $self->logger->error( "Failed set_handle (upgrade) for $schema / $table / $existing->{ cn }: $@" );
                DD::cop_it "Failed set_handle (upgrade) for $schema / $table, $existing->{ cn }: $@\n";
            }
        }
    }
    
    
    return;
}


=head2 remove_handle

Removes item(s) from the database

=cut

sub remove_handle {
    my ( $self, $schema, $table, $search_ref ) = @_;
    
    my ( $handle, $meth ) = $self->search_read( $schema => $table => $search_ref );
    my $count = 0;
    while( my $item = $handle->$meth ) {
        $self->db->delete( $self->_dn( $schema, $table, $item->{ cn } ) );
        $count ++;
    }
    
    return $count;
}


=head2 increment

Getter method for BerkeleyDB::*

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut


sub increment {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $search_ref ||= {};
    $args_ref ||= {};
    my $key         = $args_ref->{ key } || 'data';
    my $amount      = $args_ref->{ amount } || 1;
    my $last_update = $args_ref->{ last_update } || 0;
    $last_update = 'last_update' if $last_update == 1;
    
    # read (don't use the actual read, this won't be lock aware!
    my $existing = $self->get_handle( $schema, $table, $search_ref );
    
    my $increment_key   = _name( $schema, $table, $key );
    my $last_update_key = _name( $schema, $table, 'last_update' );
    
    # build write ref..
    my $write_ref;
    
    #   for existing
    if ( $existing && keys %$existing ) {
        $write_ref = $self->_upgrade_entry( $schema, $table, $existing );
    }
    #   for create (build new0)
    else {
        $write_ref = $self->_build_data( $schema, $table, $search_ref );
        $self->_satisfy_data( $schema, $table, $write_ref );
        $write_ref->{ cn } = $self->_extract_unique( $schema, $table, $search_ref );
        $write_ref->{ objectClass } = [ _name( $schema, $table ) ];
    }
    
    # increment, last update
    $write_ref->{ $increment_key } += $amount;
    $write_ref->{ $last_update_key } = time() if $last_update;
    
    # get dn
    my $dn = $self->_dn( $schema, $table, delete $write_ref->{ cn } );
    
    # modify existing ..
    if ( $existing ) {
        eval {
            $self->db->modify( $dn, replace => $write_ref );
        };
        if ( $@ ) {
            $self->logger->error( "Failed increment (upgrade) for $schema / $table: $@" );
            DD::cop_it "Failed increment (upgrade) for $schema / $table: $@\n";
        }
    }
    
    # .. or add new
    else {
        eval {
            $self->db->add( $dn, attrs => [ %$write_ref ] );
        };
        if ( $@ ) {
            $self->logger->error( "Failed increment (create) for $schema / $table: $@" );
            DD::cop_it "Failed increment (create) for $schema / $table: $@\n";
        }
    }
    
    # return new amount
    return $write_ref->{ $increment_key };
}


=head2 distinct

Implements DISTINCT method for DBD

    my @distinct = $db->distinct( schema => table => $search_ref, 'key' );

=cut

sub distinct {
    my ( $self, $schema, $table, $search_ref, $key ) = @_;
    
    my ( %distinct ) = ();
    my ( $handle, $meth ) = $self->search_read( $schema, $table, $search_ref );
    while( my $item_ref = $handle->$meth ) {
        $distinct{ $item_ref->{ $key } }++
            if defined $item_ref->{ $key }
    }
    my @res = keys %distinct;
    
    return wantarray ? @res : \@res;
}


=head2 count

Returns count for a request

=cut

sub count {
    my ( $self, $schema, $table, $search_ref ) = @_;
    my ( $handle, $meth ) = $self->search_read( $schema, $table, $search_ref );
    return $handle->count;
}


sub _dn {
    my ( $self, $schema, $table, $cn ) = @_;
    my @dn = (
        'ou='. escape_dn_value( $table ),
        'ou='. escape_dn_value( $schema ),
        $self->base
    );
    unshift @dn, 'cn='. escape_dn_value( $cn ) if $cn;
    return join( ',', @dn );
}


sub _extract_unique {
    my ( $self, $schema, $table, @refs ) = @_;
    
    my @unique_keys = $self->unique_keys( $schema, $table );
    DD::cop_it "Cannot create new row in $schema / $table, cause have no unique keys!\n"
        unless @unique_keys;
    my %unique = ();
    
    EACH_UNIQUE:
    foreach my $unique( @unique_keys ) {
        my %seen_key;
        foreach my $ref( @refs ) {
            $seen_key{ $_ }++ for keys %$ref;
            if ( defined $ref->{ $unique } ) {
                $unique{ $unique } = $ref->{ $unique };
                next EACH_UNIQUE;
            }
        }
        DD::cop_it "Require unique key part '$unique' either in search or data for $schema / $table, means one of '". join( ", ", @unique_keys ). "' but got only '". join( ", ", keys %seen_key ). "'\n";
    }
    my $unique = sha256_hex( join( '#', map {
        sprintf( '%s=%s', $_, $unique{ $_ } )
    } sort keys %unique ) );
    
    return $unique;
}

=head2 _build_data

Build ldap data from input data.

=cut

sub _build_data {
    my ( $self, $schema, $table, @refs ) = @_;
    my %data;
    my $map_ref = $self->ldap_key_map->{ $schema }->{ $table };
    my $data_types_ref = $self->data_types( $schema, $table );
    foreach my $ref( @refs ) {
        while ( my( $k, $v ) = each %$ref ) {
            next if ref( $v ) || $v =~ /\*$/;
            my $ldap_key = defined $map_ref->{ $k } ? $map_ref->{ $k } : $k;
            if ( defined $data_types_ref->{ $k } && $data_types_ref->{ $k } eq 'real' ) {
                $v = int( $v * LDAP_REAL_PRECISION );
            }
            $data{ $ldap_key } = $v;
        }
    }
    return \%data;
}


=head2 _satisfy_data

Add all required (MUST) attributes

=cut

sub _satisfy_data {
    my ( $self, $schema, $table, $data_ref ) = @_;
    my $map_ref = $self->ldap_key_map->{ $schema }->{ $table };
    while ( my ( $k, $v ) = each %{ $self->schema_defintions->{ $schema }->{ $table } } ) {
        next if index( $k, '-' ) == 0;
        my $type       = ref( $v ) ? $v->[0] : $v;
        my $ldap_value = $type eq 'integer' || $type eq 'real' ? 0 : '#';
        my $ldap_key   = defined $map_ref->{ $k } ? $map_ref->{ $k } : $k;
        $data_ref->{ $ldap_key } = $ldap_value
            unless defined $data_ref->{ $ldap_key };
    }
    return ;
}


=head2 _upgrade_entry

Upgrade entry before write

=cut

sub _upgrade_entry {
    my ( $self, $schema, $table, $data_ref ) = @_;
    my $map_ref = $self->ldap_key_map->{ $schema }->{ $table };
    my $data_types_ref = $self->data_types( $schema, $table );
    my %data = ();
    foreach my $k( keys %$data_ref ) {
        my $ldap_key = defined $map_ref->{ $k } ? $map_ref->{ $k } : $k;
        my $v = $data_ref->{ $k };
        my $t = defined $data_types_ref->{ $k } 
            ? $data_types_ref->{ $k } eq 'real'
            : 'varchar'
        ;
        if ( $t eq 'real' ) {
            $v = int( $v / LDAP_REAL_PRECISION );
        }
        elsif ( $t ne 'integer' ) {
            $v = '' if $v eq '#';
        }
        $data{ $ldap_key } = $v;
    }
    return \%data;
}


=head2 _downgrade_entry

Downgrade entry after read

=cut

sub _downgrade_entry {
    my ( $self, $schema, $table, $entry ) = @_;
    my $map_ref = $self->ldap_key_map_reverse;
    my $data_types_ref = $self->data_types( $schema, $table );
    my %data = ();
    foreach my $k( $entry->attributes ) {
        my $v = $entry->get_value( $k );
        if ( $k eq 'cn' ) {
            $data{ cn } = $v;
        }
        elsif ( defined( my $key = $map_ref->{ $k } ) ) {
            if ( defined $data_types_ref->{ $key } && $data_types_ref->{ $key } eq 'real' ) {
                $v /= LDAP_REAL_PRECISION;
            }
            $data{ $key } = $v;
        }
    }
    return \%data;
}



=head2 update_query

Returns L<Net::LDAP::Filter> object frpomk a search filter

    # binary ops
    { col1 => { '>' => 123 } } => { col1 => { '$gt' => 123 } }
    
    # array op
    { col2 => [ 1, 2, 3, 4 ] } => { col2 => { '$in' => [ 1, 2, 3, 4 ] } }
    
    # wildcard op
    { col2 => 'some word*' } => { col2 => { '$in' => qr/(?-xism:^some\ word)/ } }

=cut

sub update_query {
    my ( $self, $schema, $table, $ref ) = @_;
    $ref ||= {};
    
    my %op_match = (
        '>'  => '>=',
        '<'  => '<=',
    );
    
    my @filter = ();
    while( my ( $k, $v ) = each %$ref ) {
        
        my $type = ref( $v );
        next unless $type || $v; # ignore empty / undefined scalar
        
        my $ldap_name = escape_dn_value( _name( $schema, $table, $k ) );
        
        # from hash -> transform operators
        if ( $type eq 'HASH' ) {
            foreach my $op( keys %$v ) {
                my $vv = escape_filter_value( $v->{ $op } );
                if ( $op eq '!=' ) {
                    push @filter, sprintf( '(!(%s=%s))', $ldap_name, $vv );
                }
                else {
                    if ( $op eq '>' ) {
                        $vv ++;
                        $op = '>=';
                    }
                    elsif ( $op eq '<' ) {
                        $vv --;
                        $op = '<=';
                    }
                    $op = $op_match{ $op } if defined $op_match{ $op };
                    push @filter, sprintf( '(%s%s%s)', $ldap_name, $op, $vv );
                }
            }
        }
        
        # from array -> use '$in' operator
        elsif ( $type eq 'ARRAY' ) {
            my @or;
            foreach my $vv( @$v ) {
                push @or, sprintf( '(%s=%s)',
                    $ldap_name, escape_filter_value( $vv ) );
            }
            push @filter, '(|'. join( '', @or ). ')';
        }
        
        # ending with "*" .. keep it
        elsif ( ! $type && $v =~ /^(.*?)(?<!\\)\*$/ ) {
            my $vv = escape_filter_value( $1 );
            push @filter, sprintf( '(%s=%s*)', $ldap_name, $vv );
        }
        
        # scalar with tailing wildcard "*" -> transform to regex
        else {
            push @filter, sprintf( '(%s=%s)', $ldap_name, escape_filter_value( $v ) );
        }
    }
    
    # print Dumper( [
    #     '(&'. join( '', @filter ) . ')',
    #     Net::LDAP::Filter->new( '(&'. join( '', @filter ). ')' )
    # ] );
    
    return Net::LDAP::Filter->new( '(&'. join( '', @filter ). ')' );
}




=head2 ping_handle


=cut

sub ping_handle {
    my ( $self, $schema, $table, $columns_ref ) = @_;
    
    if ( $columns_ref ) {
        my @errors = $self->_check_ldap_schema( $schema, $table, $columns_ref );
        return 0 if @errors;
    }
    
    foreach my $ref(
        [ join( ',', 'ou='. $schema, $self->base ), {
            ou => $schema,
            objectClass => [ 'organizationalUnit' ]
        } ],
        [ join( ',', 'ou='. $table, 'ou='. $schema, $self->base ), {
            ou => $table,
            objectClass => [ 'organizationalUnit' ]
        } ]
    ) {
        my ( $base, $attrs_ref ) = @$ref;
        my $found = eval {
            $self->db->search(
                base      => $base,
                scope     => 'base',
                filter    => 'objectClass=*',
            )
        };
        if ( $@ || $found->count == 0 ) {
            $self->logger->debug3( "Ping failed to $schema / $table. Should be setup" );
            return 0;
        }
    }
    
    return 1;
}




=head2 setup_handle

Create database

So far supported:
Any database supporting VARCHAR, BLOB and INTEGER

=cut

sub setup_handle {
    my ( $self, $schema, $table, $columns_ref, $execute ) = @_;
    my @errors = $self->_check_ldap_schema( $schema, $table, $columns_ref );
    if ( @errors ) {
        $self->logger->error( "LDAP Schema incorrect: ". join( " / ", @errors ) );
        DD::cop_it "LDAP Schema incorrect: ". join( " / ", @errors ). "\n";
    }
    
    foreach my $ref(
        [ join( ',', 'ou='. $schema, $self->base ), {
            ou => $schema,
            objectClass => [ 'organizationalUnit' ]
        } ],
        [ join( ',', 'ou='. $table, 'ou='. $schema, $self->base ), {
            ou => $table,
            objectClass => [ 'organizationalUnit' ]
        } ]
    ) {
        my ( $base, $attrs_ref ) = @$ref;
        my $found = eval {
            $self->db->search(
                base      => $base,
                scope     => 'base',
                filter    => 'objectClass=*',
            )
        };
        if ( $@ || $found->count == 0 ) {
            if ( $execute ) {
                eval { $self->db->add( $base, attrs => [ %$attrs_ref ] ) };
                if ( $@ ) {
                    $self->logger->error( "Failed to setup $schema / $table ($base): $@" );
                    DD::cop_it "Failed to setup $schema / $table ($base): $@\n";
                }
            }
        }
        else {
            $self->logger->debug3( "Setup database successfull $schema / $table" );
        }
    }
    
    return 1;
}

=head2 after_register

=cut

sub after_register {
    my ( $self, $schema_def_ref, $additive ) = @_;
    my ( %mapping, %mapping_reverse );
    $schema_def_ref ||= $self->schema_defintions;
    while ( my ( $schema, $schema_ref ) = each %$schema_def_ref ) {
        my $schema_map_ref = $mapping{ $schema } ||= {};
        while ( my ( $table, $table_ref ) = each %$schema_ref ) {
            my $table_map_ref = $schema_map_ref->{ $table } ||= {};
            while ( my( $k, $v ) = each %$table_ref ) {
                my $ldap_key = _name( $schema, $table, $k );
                $table_map_ref->{ $k } = $ldap_key;
                $mapping_reverse{ $ldap_key } = $k;
            }
        }
    }
    
    if ( $additive ) {
        $self->{ ldap_key_map } ||= {};
        $self->{ ldap_key_map }->{ $_ } = $mapping{ $_ }
            for keys %mapping;
        $self->{ ldap_key_map_reverse } ||= {};
        $self->{ ldap_key_map_reverse }->{ $_ } = $mapping_reverse{ $_ }
            for keys %mapping_reverse;
    }
    else {
        $self->{ ldap_key_map } = \%mapping;
        $self->{ ldap_key_map_reverse } = \%mapping_reverse;
    }
    return ;
}



=head2 _check_ldap_schema

=cut

sub _check_ldap_schema {
    my ( $self, $schema, $table, $columns_ref ) = @_;
    
    my $db = $self->_use_net_ldap_api
        ? $self->_create_net_ldap
        : $self->db
    ;
    my $ldap_schema = $db->schema;
    my ( @errors, @warnings, @create ) = ();
    
    #
    # CHECK ATTRIBUTES AND CLASSES
    #
    
    my %columns = %$columns_ref;
    my $unique_ref = delete $columns{ -unique } || [];
    my $index_ref = delete $columns{ -index } || [];
    my $oc_name = _name( $schema, $table );
    
    my %found_attrs = map {
        ( $_->{ name } => $_ )
    } $ldap_schema->all_attributes();
    
    my %ldap_columns;
    foreach my $column( sort keys %columns ) {
        my $ldap_column = _name( $schema, $table, $column );
        $ldap_columns{ $ldap_column } ++;
        unless ( defined $found_attrs{ $ldap_column } ) {
            push @errors, sprintf( 'Missing attribute "%s" for "%s"', $ldap_column, $oc_name );
        }
    }
    
    my %found_ocs = map {
        ( $_->{ name } => $_ ); 
    } $ldap_schema->all_objectclasses();
    if ( $found_ocs{ $oc_name } ) {
        my %must = map {
            ( $_ => 1 )
        } @{ $found_ocs{ $oc_name }->{ must } || [] };
        foreach my $ldap_column( sort keys %ldap_columns ) {
            unless ( defined $must{ $ldap_column } ) {
                push @errors, sprintf( 'Missing MUST attribute "%s" in class "%s"',
                    $oc_name, $ldap_column );
            }
        }
    }
    else {
        push @errors, sprintf( 'Missing class "%s"', $oc_name ); 
    }
    
    $db->disconnect
        if $self->_use_net_ldap_api;
    
    return @errors;
}



sub _create_net_ldap {
    my ( $self ) = @_;
    return Net::LDAP->new(
        $self->host,
        scheme  => $self->scheme,
        onerror => 'die',
        %{ $self->config }
    );
}


=head1 PRIVATE STATIC METHODS

=cut

sub _name {
    my ( @args ) = @_;
    return 'cn' if $args[-1] eq 'cn';
    return _camel( 'decency_'. join( '_', @args ) );
}

sub _camel {
    my ( $str ) = @_;
    $str =~ s/_([a-z])/uc($1)/egms;
    $str =~ s/_$//;
    return $str;
}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

package _Net_LDAP_Search;

use Data::Dumper;
use constant {
    LDAP_REAL_PRECISION => 10_000
};
use base qw/ Net::LDAP::Search /;

sub get_next_entry {
    my ( $r ) = @_;
    my $entry = $r->pop_entry();
    return if ! $entry || $entry->get_value( 'ou' );
    my $map_ref = $r->{ ldap_key_map_reverse };
    my $data_types_ref = $r->{ data_types };
    
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



1;

package Mail::Decency::Helper::Database;

use Mouse;
with qw/
    Mail::Decency::Core::Locker
/;
use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use Data::Pager;
use Digest::SHA qw/ sha256_hex /;
use Storable qw/ freeze /;
use Time::HiRes qw/ usleep ualarm /;

use Mail::Decency::Helper::Debug;

=head1 NAME

Mail::Decency::Helper::Database

=head1 DESCRIPTION

Base class for all databases

=head1 SYNPOSIS

Create a new datbaase like this:

    Mail::Decency::Helper::Database->create( MongoDB => $config_ref );


=head1 CLASS ATTRIBUTES

=head2 type : Str

The type of the database (DBD, MongoDB)

=cut

has type   => ( is => "rw", isa => "Str" );

=head2 logger : CodeRef

Log-Handler method

=cut

has logger => ( is => "rw", isa => "Mail::Decency::Helper::Logger" );

# =head2 unique_keys : HashRef[HashRef[HashRef[HashRef[Bool]]]]

# Remembers unique keys.. filled via setup method

#     { schema => { table => { key_name => { key => 1, key2 => 1 } } } }

# =cut

# has unique_keys => ( is => "rw", isa => 'HashRef[HashRef[HashRef[HashRef[Bool]]]]', default => sub {{}} );

=head2 server : Mail::Decency::Server

Back reference to the server

=cut

has server => ( is => "rw" );

=head2 cache_enabled : Bool

Wheter experimental Caching is enabled

=cut

has cache_enabled => ( is => "rw", isa => 'Bool', default => 0 );

=head2 cache_timeout : Int

Timeout for experimental caching

=cut

has cache_timeout => ( is => "rw", isa => 'Int', default => 300 );

=head2 schema_defintions : HashRef

Schema definitions of all module databases

=cut

has schema_defintions => ( is => "rw", isa => 'HashRef', default => sub { {} } );



=head1 METHODS

=head2 create $type, $args_ref

Returns a new instance of the created database object

    my $database = Mail::Decency::Helper::Database->create( DBD => $args_ref );

=over

=item * $type

Either DBD or MongoDB for now

=item * $args_ref

HashRef of constrauctions variabels for the module's new-method

=back

=cut

sub BUILD {}

sub create {
    my ( $class, $type, $args_ref, $server ) = @_;
    
    my $module = "Mail::Decency::Helper::Database::$type";
    my $ok = eval "use $module; 1";
    unless ( $ok ) {
        DD::cop_it "Unsupported database '$type': $@\n";
    }
    
    # create and return instance
    my $obj;
    my %create = ( %$args_ref, type => $type );
    if ( $server ) {
        $create{ server } = $server;
    }
    #$create{ locker_pid } = $args_ref->{ locker_pid } || $server->locker_pid || $$;
    
    eval {
        $obj = $module->new( %create );
    };
    DD::cop_it "Connection error for '$type': $@" if $@;
    return $obj;
}


=head2 DEMOLISH

Remove lockers, disconnects from DBs

=cut
sub DEMOLISH {}
before DEMOLISH => sub {
    my ( $self ) = @_;
    $self->disconnect;
};

=head2 search

Search in database using a search query hashref. Limitiation, offset and ordereing is possible

    # dataset looks like this
    # { col1 => 'string', col2 => 123, col3 => 333 }
    
    my $array_ref = $db->search( schema => table => {
        col1 => 'beginning with*',  # SQL: col1 LIKE "beginning with%"
        col2 => { '>' => 150 },     # greater then
        col3 => [ 100, 200, 300 ]   # SQL: col3 IN ( 100, 200, 300 )
    }, {
        limit => 100,
        offset => 400,
        order  => {
            col2 => 'desc'
        }
    } );
    print "Found ". ( $#$array_ref ). " entries\n";
    
    my @array = $db->search( schema => table => $search_ref, $args_ref );
    print "Found ". ( $#array ). " entries\n";

=cut

sub search {
    my ( $self, @args ) = @_;
    if ( $self->cache_enabled ) {
        return $self->search_cached( @args );
    }
    else {
        return $self->search_handle( @args );
    }
}

=head2 search_cached

=cut

sub search_cached {
    my ( $self, $schema, $table, $search_ref, $args_ref, @args ) = @_;
    
    # get cache instancw
    my $cache = $self->server->cache;
    
    # search key (including args)
    my $key = 'DB:SEARCH:'. sha256_hex( join( ':',
        $schema, $table, freeze( $search_ref || {} ), freeze( $args_ref || {} ) ) );
    
    # found -> return result
    if ( my $cached = $cache->get( $key ) ) {
        return wantarray ? @{ $cached->{ result } } : $cached->{ result };
    }
    
    # perform search on database
    my @res = $self->search_handle( $schema, $table, $search_ref, $args_ref, @args );
    
    # write to cache
    $cache->set( $key, { result => \@res } );
    
    # write mapping key (to allow purging cache excluding the args)
    my $map_key = 'DB:MAPSEARCH:'. sha256_hex( join( ':',
        $schema, $table, freeze( $search_ref || {} ) ) );
    my $map_ref = $cache->get( $map_key ) || {};
    $map_ref->{ $key } = 1;
    $cache->set( $map_key, $map_ref, $self->cache_timeout );
    
    return wantarray ? @res : \@res;
}

=head2 search_read

Same signature as search. Returns a read handle and a read method instead of the actual result. Good choice for huge results.

    my ( $res, $handle ) = $db->search_read( schema => table => $search_ref, $args_ref );
    while ( my $item = $res->$handle ) {
        print Dumper( $item );
    }

=cut

sub search_read { DD::cop_it ref( $_[0] ). " needs to implement search_read" }

=head2 count

Returns count of entries in database

    my $count = $db->count( schema => table => $search_ref );

=cut

sub count { DD::cop_it ref( $_[0] ). " needs to implement count" }

=head2 get

Searches and returns single entry from database

See parse_data method for return contexts.

    my $entry_ref = $db->get( schema => table => $search_ref );

=cut

sub get {
    my ( $self, @args ) = @_;
    if ( $self->cache_enabled ) {
        return $self->get_cached( @args );
    }
    else {
        return $self->get_handle( @args );
    }
}

=head2 get_cached

=cut

sub get_cached {
    my ( $self, $schema, $table, $search_ref, @args ) = @_;
    my $cache = $self->server->cache;
    my $key = 'DB:GET:'. sha256_hex( join( ':', $schema, $table, freeze( $search_ref ) ) );
    if ( my $cached = $cache->get( $key ) ) {
        return $cached->{ result };
    }
    my $res = $self->get_handle( $schema, $table, $search_ref, @args );
    $cache->set( $key, { result => $res }, $self->cache_timeout );
    return $res;
}


=head2 set

Writes to database. Can affect multiple entries. Tries update / insert.

    $db->set( schema => table => {
        col1 => 'all those*'
    }, {
        col2 => 123
    } );

=cut

sub set {
    my ( $self, $schema, $table, $search_ref, $data_ref, @args ) = @_;
    $self->set_handle( $schema, $table, $search_ref, $data_ref, @args );
    if ( $self->cache_enabled ) {
        my $cache = $self->server->cache;
        my $sha = sha256_hex( join( ':', $schema, $table, freeze( $search_ref ) ) );
        my @keys = ( 'DB:GET:'. $sha, 'DB:SEARCH:'. $sha );
        my $map_key = 'DB:MAPSEARCH:'. $sha;
        if ( my $map_ref = $cache->get( $map_key ) ) {
            push @keys, keys %$map_ref;
            push @keys, $map_key;
        }
        $cache->remove( $_ ) for @keys;
    }
    return ;
}

=head2 increment

Increments a single column of a single entry

    # update the key called "data" in the table
    my $new_value = $db->increment( schema => table => {
        col2 => 444
    } );
    
    # update the key called "data" in the table
    my $new_value = $db->increment( schema => table => {
        col2 => 444
    }, {
        key         => 'col3', # update column 'col3'
        amount      => 4,      # increment by 4
        last_update => 1       # update the column 'last_update', set timestampe
                               # can be set to a column name (other then last_update)
                               # which should be updated instead
    } );

=cut

sub increment { DD::cop_it ref( $_[0] ). " needs to implement increment" }

=head2 distinct

Implements DISTINCT method. You can retreve a set of distinct vaulues for
a given search

    my @distinct_values
        = $db->distinct( schema => table => $search_ref, 'column' );

=cut

sub distinct { DD::cop_it ref( $_[0] ). " needs to implement distinct" }

=head2 remove

Remove all selected entries. Caution: will remove all entries found by search!

    $db->remove( schema => table => {
        col1 => 'all those*'
    } );

=cut

sub remove {
    my ( $self, $schema, $table, $search_ref, @args ) = @_;
    $self->remove_handle( $schema, $table, $search_ref, @args );
    if ( $self->cache_enabled ) {
        my $cache = $self->server->cache;
        my $sha = sha256_hex( join( ':', $schema, $table, freeze( $search_ref ) ) );
        my @keys = ( 'DB:GET:'. $sha, 'DB:SEARCH:'. $sha );
        my $map_key = 'DB:MAPSEARCH:'. $sha;
        if ( my $map_ref = $cache->get( $map_key ) ) {
            push @keys, keys %$map_ref;
            push @keys, $map_key;
        }
        $cache->remove( $_ ) for @keys;
    }
    return ;
}



=head2 ping

=cut

sub ping {
    my ( $self, $schema, $table, $table_ref ) = @_;
    
    if ( ref( $table ) ) {
        my $ok = 1;
        PING_EACH_SCHEMA:
        while( my( $schema, $schema_ref ) = each %$table ) {
            while( my( $table, $table_ref ) = each %$schema_ref ) {
                $ok = 0 unless $self->ping_handle( $schema, $table, $table_ref );
                last PING_EACH_SCHEMA unless $ok;
            }
        }
        return $ok;
    }
    
    return $self->ping_handle( $schema, $table, $table_ref );
}



=head2 setup

=cut

sub setup {
    my ( $self, @args ) = @_;
    
    if ( scalar @args >= 3 ) {
        my ( $schema, $table, $table_ref, $args_ref ) = @args;
        $args_ref ||= { execute => 0, test => 0, register => 0 };
        $self->register( { $schema => { $table => $table_ref } } );
        return 1 if $args_ref->{ test } && $self->ping_handle( $schema, $table, $table_ref );
        return $self->setup_handle( $schema, $table, $table_ref, $args_ref->{ execute } );
    }
    else {
        my $ok = 1;
        my ( $schema_defintion_ref, $args_ref ) = @args;
        $args_ref ||= { execute => 0, test => 0, register => 0 };
        $self->register( $schema_defintion_ref );
        EACH_SCHEMA_SETUP:
        while( my ( $schema, $schema_ref ) = each %$schema_defintion_ref ) {
            while( my ( $table, $table_ref ) = each %$schema_ref ) {
                next
                    if $args_ref->{ test } && $self->ping_handle( $schema, $table, $table_ref );
                $ok = 0 unless $self->setup_handle(
                    $schema, $table, $table_ref, $args_ref->{ execute } );
                last EACH_SCHEMA_SETUP unless $ok;
            }
        }
        return $ok;
    }
}

=head2 assure_setup

=cut

sub assure_setup {
    my ( $self, $schema_defintion_ref ) = @_;
    $self->register( $schema_defintion_ref );
    
    EACH_SCHEMA_SETUP:
    while( my ( $schema, $schema_ref ) = each %$schema_defintion_ref ) {
        while( my ( $table, $table_ref ) = each %$schema_ref ) {
            $self->setup_handle( $schema, $table, $table_ref, 1 )
                unless $self->ping_handle( $schema, $table, $table_ref );
        }
    }
    
}


=head2 register

Registers schema definition to database. Thereby it will be possible to access unique keys and indexes later on.

=cut

sub register {
    my ( $self, $schema_defintion_ref ) = @_;
    my $orig_ref = $self->schema_defintions;
    while( my ( $schema, $schema_ref ) = each %$schema_defintion_ref ) {
        my $orig_schema_ref = $orig_ref->{ $schema } ||= {};
        while( my ( $table, $table_ref ) = each %$schema_ref ) {
            $orig_schema_ref->{ $table } = $table_ref;
        }
    }
    $self->after_register() if $self->can( 'after_register' );
    return;
}





=head2 update_data

Transforms flat (scalar) values into { data => $value } hashrefs

=cut

sub update_data {
    my ( $self, $data ) = @_;
    return $data || {};
    # return $data if ref( $data );
    # return { data => $data };
}

=head2 parse_data $data_ref

Transforms hashref values in an array context from { value => $value } to ( $value )

In array-context, it will return the content of the "data" field, if any

Can be modified in derived modules.

=cut

sub parse_data {
    my ( $self, $data ) = @_;
    return $data;
    # return unless defined $data;
    # return wantarray ? ( $data ) : { data => $data } unless ref( $data );
    # return wantarray ? ( $data->{ data } ) : $data;
}



=head2 update_query $query_ref

Update method for search query. Can be overwritten/extended in derived modules.

=cut

sub update_query {
    my ( $self, $query_ref ) = @_;
    return $query_ref if ref( $query_ref );
    return { key => $query_ref };
}


=head2 get_unique_key_query

=cut

sub get_unique_key_query {
    my ( $self, $schema, $table, $found_ref ) = @_;
    my @unique_keys = $self->unique_keys( $schema, $table );
    my @found = ();
    my %query = ();
    foreach my $key( @unique_keys ) {
        next unless defined $found_ref->{ $key };
        $query{ $key } = $found_ref->{ $key };
        push @found, $key;
    }
    
    # found valid unqiue key query
    return \%query
        if scalar( @unique_keys ) == scalar( @found );
    
    return;
    
}


sub do_lock      { my $s = shift; $s->server ? $s->server->do_lock( 'database', @_ ) : 0 }
sub do_unlock    { my $s = shift; $s->server ? $s->server->do_unlock( 'database', @_ ) : 0 }
sub read_lock    { my $s = shift; $s->server ? $s->server->read_lock( 'database', @_ ) : 0 }
sub read_unlock  { my $s = shift; $s->server ? $s->server->read_unlock( 'database', @_ ) : 0 }
sub write_lock   { my $s = shift; $s->server ? $s->server->write_lock( 'database', @_ ) : 0 }
sub write_unlock { my $s = shift; $s->server ? $s->server->write_unlock( 'database', @_ ) : 0 }
sub usr_lock     { my $s = shift; $s->server ? $s->server->usr_lock( 'database', @_ ) : 0 }
sub usr_unlock   { my $s = shift; $s->server ? $s->server->usr_unlock( 'database', @_ ) : 0 }


=head2 pageset

Returns pageset result

    my ( $results_ref, $pager ) = $db->pageset( schema => table => {
        search => 123
    }, {
        limit => 10,
        page  => 3 
    } );

Page starts at 1 not 0!

=cut

sub pageset {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $args_ref ||= {};
    $args_ref->{ limit } ||= 10;
    $args_ref->{ page }  ||= 1;
    
    my $count  = $self->count( $schema, $table, $search_ref );
    my $offset = $args_ref->{ limit } * ( $args_ref->{ page } - 1 );
    my $pages  = int( $count / $args_ref->{ limit } ) + ( $count % $args_ref->{ limit } > 0 ? 1 : 0 );
    
    my $pager = Data::Pager->new( {
        current => $args_ref->{ page },
        offset  => $args_ref->{ limit },
        perpage => 10,
        limit   => $count - $args_ref->{ limit }
    } );
    
    if ( $count > $offset ) {
        my $results_ref = $self->search( $schema, $table, $search_ref, {
            limit  => $args_ref->{ limit },
            order  => $args_ref->{ order },
            offset => $offset
        } );
        return ( $results_ref, $pager );
    }
    else {
        return ( [], $pager );
    }
}


=head2 unique_keys

Returns array of unique keys for a schema / table

=cut

sub unique_keys {
    my ( $self, $schema, $table ) = @_;
    if ( defined( my $schema_ref = $self->schema_defintions->{ $schema } ) ) {
        if ( defined( my $table_ref = $schema_ref->{ $table } ) ) {
            return @{ $table_ref->{ -unique } || [] };
        }
    }
    return;
}


=head2 unique_keys

Returns array of unique keys for a schema / table

=cut

sub data_types {
    my ( $self, $schema, $table ) = @_;
    if ( defined( my $schema_ref = $self->schema_defintions->{ $schema } ) ) {
        if ( defined( my $table_ref = $schema_ref->{ $table } ) ) {
            return { map {
                ( $_ => ref( $table_ref->{ $_ } )
                    ? $table_ref->{ $_ }->[0]
                    : $table_ref->{ $_ }
                );
            } grep {
                ! /^-/
            } keys %{ $table_ref } };
        }
    }
    return;
}


=head2 check_table

Has to be overwritten by database implementation

=cut

sub check_table {
    warn "'check_table' not implemented for ". ref( shift ). "\n";
    return 0;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

package Mail::Decency::Helper::Database::DBD;

use Mouse;
extends qw/
    Mail::Decency::Helper::Database
/;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );


use Data::Dumper;
use DBIx::Connector;
use SQL::Abstract::Limit;

has db         => ( is => "ro", isa => "DBIx::Connector" );
has sql        => ( is => "ro", isa => "SQL::Abstract" );
has args       => ( is => "ro", isa => "ArrayRef", required => 1 );
has quote_char => ( is => 'rw', isa => 'Str', default => q{"} );
has create_conf => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

sub BUILD {
    my ( $self ) = @_;
    
    eval {
        # connect via fork save connector
        my @args = @{ $self->args };
        push @args, undef while( scalar @args < 3 );
        my $dbh = DBIx::Connector->new( @args, { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
        
        # use abstracted api
        $self->{ db } = $dbh;
    };
    die "Error creating DBD insances: $@\n" if $@;
    
    $self->{ sql } = SQL::Abstract::Limit ->new(
        #quote_char=> $self->quote_char
        limit_dialect => $self->{ db }->dbh
    );
    
    # quotings
    if ( $self->args->[0] =~ /^dbi:mysql:/i ) {
        $self->quote_char( q{`} );
        $self->create_conf->{ tables } = [ 'TYPE=myisam', 'DEFAULT CHARSET=latin1' ];
    }
    
    return $self;
}


=head2 disconnect

Close connection

=cut

sub disconnect {
    my ( $self ) = @_;
    $self->db->disconnect
        if $self->db;
}


=head2 search_handle

Search in database for a key

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut

sub search_handle {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $args_ref ||= { no_lock => 0 };
    my $no_lock = $args_ref->{ no_lock };
    
    $self->read_lock unless $no_lock; # accquire semaphore
    $search_ref = $self->update_query( $search_ref );
    
    my ( $stm, @bind, $sth );
    eval {
        ( $stm, @bind ) = $self->sql->select(
            "${schema}_${table}" => [ '*' ],
            $search_ref,
            $self->update_order( $args_ref->{ order } ) || {},
            $args_ref->{ limit } ||= 0,
            $args_ref->{ offset } ||= 0
        );
        $ENV{ PRINT_SQL } && warn "SQL> $stm (@bind)\n";
        $sth = $self->db->dbh->prepare_cached( $stm );
        $sth->execute( @bind );
    };
    if ( my $db_err = ( $@ || $DBI::errstr ) ) {
        $self->read_unlock  unless $no_lock;
        die "!! DATABASE ERROR: $db_err  [@bind]!!\n";
    }
    
    my @res;
    while ( my $res = $sth->fetchrow_hashref ) {
        push @res, $res;
    }
    
    $self->read_unlock unless $no_lock; # release semaphore
    return wantarray ? @res : \@res;
}


=head2 search_read

Returns read handle and read method name for massive read actions

=cut

sub search_read {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $args_ref ||= {};
    $search_ref = $self->update_query( $search_ref );
    
    my $sth;
    eval {
        my ( $stm, @bind ) = $self->sql->select(
            "${schema}_${table}" => [ '*' ],
            $search_ref,
            $self->update_order( $args_ref->{ order } ) || {},
            $args_ref->{ limit } ||= 0,
            $args_ref->{ offset } ||= 0
        );
        $sth = $self->db->dbh->prepare_cached( $stm );
        $ENV{ PRINT_SQL } && warn "SQL> $stm (@bind)\n";
        $sth->execute( @bind );
    };
    die "Database error: $DBI::errstr\n" if $DBI::errstr;
    
    return ( $sth, 'fetchrow_hashref' );
}


=head2 get_handle

Search in database for a key

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut

sub get_handle {
    my ( $self, $schema, $table, $search_ref, $no_lock ) = @_;
    $search_ref = $self->update_query( $search_ref );
    my ( $ref ) = $self->search_handle( $schema => $table => $search_ref, { no_lock => $no_lock } );
    my $res = $self->parse_data( $ref );
    return $res;
}


=head2 set_handle

Getter method for BerkeleyDB::*

CAUTION: use with care. Always provide ALL search keys, not only one of a kind!

=cut

sub set_handle {
    my ( $self, $schema, $table, $search_ref, $data_ref, $args_ref ) = @_;
    $args_ref ||= {};
    $self->write_lock; # accquire semaphore
    
    $search_ref = $self->update_query( $search_ref );
    
    $data_ref ||= $search_ref;
    $data_ref = $self->update_data( $data_ref );
    
    my ( $stm, @bind );
    
    #
    # UPDATE ALL
    #   none found -> no update
    #
    if ( $args_ref->{ update_all } ) {
        ( $stm, @bind )
            = $self->sql->update( "${schema}_${table}" => $data_ref, $search_ref );
    }
    
    #
    # UPSERT
    #   update existing or create new
    #
    else {
        
        # get existing ..
        my $existing = $self->get_handle( $schema => $table => $search_ref, 1 );
        
        # update ..
        if ( $existing ) {
            ( $stm, @bind )
                = $self->sql->update( "${schema}_${table}" => $data_ref,
                $existing, 1 );
        }
        
        # insert ..
        else {
            ( $stm, @bind )
                = $self->sql->insert( "${schema}_${table}" => { %$search_ref, %$data_ref } );
        }
    }
    
    # exec ..
    eval {
        $ENV{ PRINT_SQL } && warn "SQL> $stm (@bind)\n";
        my $sth = $self->db->dbh->prepare( $stm );
        $sth->execute( @bind );
        #$self->db->dbh->commit;
    };
    if ( $@ || $DBI::errstr ) {
        $self->write_unlock; # release semaphore
        die "!! DATABASE ERROR ($stm): $DBI::errstr  [". join( ", ", @bind ). "]!!\n";
    }
    
    $self->write_unlock; # release semaphore
    
    return;
}


=head2 count

Returns count for a request

=cut

sub count {
    my ( $self, $schema, $table, $search_ref ) = @_;
    
    my $count = 0;
    eval {
        my ( $stm, @bind ) = $self->sql->select(
            "${schema}_${table}" => [ 'COUNT( * )' ],
            $search_ref
        );
        my $sth = $self->db->dbh->prepare_cached( $stm );
        $ENV{ PRINT_SQL } && warn "SQL> $stm (@bind)\n";
        $sth->execute( @bind );
        
        ( $count ) = $sth->fetchrow_array();
    };
    
    die "Database error: $DBI::errstr\n" if $DBI::errstr;
    
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
    my $last_update = $args_ref->{ last_update } ? 'last_update' : '';
    
    # lock for increment
    $self->usr_lock;
    
    # read (don't use the actual read, this won't be lock aware!
    $search_ref = $self->update_query( $search_ref );
    my ( $ref ) = $self->search( $schema => $table => $search_ref );
    $ref = $self->parse_data( $ref );
    
    # increment data
    $ref->{ $key } += $amount;
    $ref->{ $last_update } = time() if $last_update;
    
    # write data (without locks)
    $self->set( $schema => $table => $search_ref => $ref );
    
    # unlock after increment
    $self->usr_unlock;
    
    return $ref->{ $key };
}


=head2 distinct

Implements DISTINCT method for DBD

    my @distinct = $db->distinct( schema => table => $search_ref, 'key' );

=cut

sub distinct {
    my ( $self, $schema, $table, $search_ref, $key ) = @_;
    
    $search_ref = $self->update_query( $search_ref );
    
    my $sth;
    
    my ( $stm, @bind ) = $self->sql->select(
        "${schema}_${table}" => [ 'DISTINCT( '. quotemeta( $key ). ' )' ],
        $search_ref,
    );
    $sth = $self->db->dbh->prepare_cached( $stm );
    
    $self->read_lock;
    eval {
        $ENV{ PRINT_SQL } && warn "SQL> $stm (@bind)\n";
        $sth->execute( @bind );
    };
    
    if ( $@ || $DBI::errstr ) {
        $self->read_unlock; # release semaphore
        die "!! DATABASE ERROR: $DBI::errstr [@bind]!!\n";
    }
    
    my @res = map { $_->[0] } @{ $sth->fetchall_arrayref() };
    
    $self->read_unlock; # release semaphore
    
    return wantarray ? @res : \@res;
}



=head2 remove_handle

Removes item(s) from the database

=cut

sub remove_handle {
    my ( $self, $schema, $table, $search_ref ) = @_;
    
    $self->write_lock; # accquire semaphore
    
    eval {
        my ( $stm, @bind ) = $self->sql->delete( "${schema}_${table}" => $search_ref );
        my $sth = $self->db->dbh->prepare( $stm );
        $ENV{ PRINT_SQL } && warn "SQL> $stm (@bind)\n";
        $sth->execute( @bind );
    };
    if ( $@ || $DBI::errstr ) {
        $self->write_unlock; # release semaphore
        die "Error in remove: $DBI::errstr\n"; 
    };
    
    $self->write_unlock; # release semaphore
    
    return;
}


=head2 ping_handle

Check wheter schema/table exists

=cut

sub ping_handle {
    my ( $self, $schema, $table ) = @_;
    
    my ( $stm, @bind ) = $self->sql->select( "${schema}_${table}" => [ 'COUNT( id )' ] );
    $self->db->dbh->{ PrintError } = 0;
    
    eval {
        my $sth = $self->db->dbh->prepare( $stm );
        if ( $sth ) {
            $ENV{ PRINT_SQL } && warn "SQL> $stm\n";
            $sth->execute;
            my ( $amount ) = $sth->fetchrow_array;
        }
    };
    my $ok = ! $DBI::errstr && ! $@;
    
    return $ok;
}


=head2 setup_handle

Create database

So far supported:
Any database supporting VARCHAR, BLOB and INTEGER

=cut

sub setup_handle {
    my ( $self, $schema, $table, $columns_ref, $execute ) = @_;
    
    my ( @columns, @indices, @uniques ) = ();
    while( my ( $name, $ref ) = each %$columns_ref ) {
        if ( $name eq '-index' ) {
            my @index = @{ $columns_ref->{ -index } };
            if ( ref( $index[0] ) ) {
                foreach my $idx_ref( @index ) {
                    my $idx = join( "_", @$idx_ref );
                    push @indices, [
                        "${schema}_${table}_${idx} ON ${schema}_${table}",
                        $idx_ref
                    ];
                }
            }
            else {
                my $idx = join( "_", @index );
                push @indices, [
                    "${schema}_${table}_${idx} ON ${schema}_${table}",
                    \@index
                ];
            }
        }
        elsif ( $name eq '-unique' ) {
            my $idx = join( "_", @{ $columns_ref->{ -unique } } );
            push @uniques, [
                "${schema}_${table}_${idx} ON ${schema}_${table}",
                $columns_ref->{ -unique }
            ];
        }
        elsif ( index( $name, '-' ) == 0 ) {
            # ignore
        }
        else {
            my $type = ref( $ref ) eq 'ARRAY'
                ? ( $#$ref == 0
                    ? $ref->[0]
                    : "$ref->[0]($ref->[1])"
                )
                : $ref
            ;
            $name = $self->quote_char. $name. $self->quote_char;
            push @columns, "$name $type";
        }
    }
    push @columns, "id INTEGER PRIMARY KEY";
    
    my @stm;
    
    push @stm, do {
        my $sql = scalar $self->sql->generate(
            'create table', "${schema}_${table}" => \@columns );
        $sql .= join( ' ', @{ $self->create_conf->{ tables } } )
            if defined $self->create_conf->{ tables };
        $sql;
    };
    
    push @stm, scalar $self->sql->generate(
        'create index', $_->[0] => [ map {
            $self->quote_char. $_ . $self->quote_char
        } @{ $_->[1] } ] )
        for @indices;
    
    push @stm, scalar $self->sql->generate(
        'create unique index', $_->[0] => [ map {
            $self->quote_char. $_ . $self->quote_char
        } @{ $_->[1] } ] )
        for @uniques;
    
    unless ( $execute ) {
        print join( "\n",
            "-- TABLE: ${schema}_${table} (SQLITE):",
            join( ";\n", @stm ),
        ). ";\n";
        return 0;
    }
    else {
        foreach my $stm( @stm ) {
            eval {
                $ENV{ PRINT_SQL } && warn "SQL> $stm\n";
                $self->db->dbh->do( "$stm;" );
            };
            if ( $@ || $DBI::errstr ) {
                die "DBD Error ($stm): $DBI::errstr / $@";
            }
        }
        return 1;
    }
}




=head2 update_data

Update input data for write 

Transforms any complex "data" key into YAML

=cut

sub update_data {
    my ( $self, $data_ref ) = @_;
    $data_ref = $self->maybe::next::method( $data_ref );
    if ( defined $data_ref->{ data } && ref( $data_ref->{ data } ) ) {
        $data_ref->{ data } = YAML::Dump( $data_ref->{ data } );
    }
    return wantarray ? ( $data_ref->{ data } ) : $data_ref;
}

=head2 parse_data

Parse data after read. Parses any YAML data in "data" key into perl object

=cut

sub parse_data {
    my ( $self, $data_ref ) = @_;
    $data_ref = $self->maybe::next::method( $data_ref );
    if ( $data_ref && ref( $data_ref ) && defined $data_ref->{ data } ) {
        eval {
            $data_ref->{ data } = YAML::Load( $data_ref->{ data } );
        };
    }
    return $data_ref;
}

=head2 update_query

Implements the word-beginning-wildccard search

=cut

sub update_query {
    my ( $self, $query_ref ) = @_;
    $query_ref ||= {};
    
    foreach my $k( keys %$query_ref ) {
        my $type = ref( $k );
        if ( ! $type && $query_ref->{ $k } =~ /^(.+?)(?<!\\)\*$/ ) {
            my $v = $1;
            $query_ref->{ $k } = { like => "$v\%" };
        }
    }
    
    return $query_ref;
}


=head2 update_query_from_unique_keys

Updates a search-query in the context of set, if 

=cut

sub update_query_from_unique_keys {
    my ( $self, $query_ref, $schema, $table, $found_ref ) = @_;
    
    my $unique_ref = $self->unique_keys;
    if ( defined $unique_ref->{ $schema } && defined( my $uref = $unique_ref->{ $schema }->{ $table } ) ) {
        my @found = ();
        my @keys  = keys %$uref;
        foreach my $key( keys %$uref ) {
            next if defined $query_ref->{ $key };
            push @found, $key if defined $found_ref->{ $key };
        }
        if ( scalar( @keys ) == scalar( @found ) ) {
            $query_ref->{ $_ } = $found_ref->{ $_ }
                for @keys;
        }
    }
    
    return $query_ref;
}

=head2 update_order

=cut

sub update_order {
    my ( $self, $order_ref ) = @_;
    return unless $order_ref;
    
    my @order = ();
    foreach my $ref( @$order_ref ) {
        push @order, "$ref->{ col } $ref->{ dir }";
    }
    
    return \@order;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

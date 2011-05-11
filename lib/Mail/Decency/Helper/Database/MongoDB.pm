package Mail::Decency::Helper::Database::MongoDB;

use Mouse;
extends qw/
    Mail::Decency::Helper::Database
/;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use Tie::IxHash;
use MongoDB 0.35;
use Carp qw/ croak /;
use Time::HiRes qw/ usleep ualarm /;

our $EXECUTE_TIMEOUT = 5_000_000;
our $CONNECT_TIMEOUT = 5_000_000;


=head1 CLASS VARIABLES

=head2 db : MongoDB::Connection

Instances of a L<MongoDB::Connection>

=cut

has db       => ( is => "ro" ); # Undef | MongoDB::Database

=head2 host : Str

Host to connect to. Can be two hosts for left and right side (separated by ",")

Default: 127.0.0.1

=cut

has host     => ( is => "ro", isa => "Str", default => "127.0.0.1" );

=head2 port : Str

Port to database. If mutliple hosts are provided and have differnt ports, also list separated by ","

Default: 27017

=cut

has port     => ( is => "ro", isa => "Str", default => "27017" );

=head2 user : Str

Database user, if any

=cut

has user     => ( is => "ro", isa => "Str", predicate => 'use_auth' );

=head2 pass : Str

Database password, if any

=cut

has pass     => ( is => "ro", isa => "Str" );

=head2 database : Str

Database to connect to

Default: decency

=cut

has database => ( is => "ro", isa => "Str", default => "decency" );

=head2 execute_timeout : Int

Execute timeout in micro seconds..

Default: 5_000_000 (5 seconds)

=cut

has execute_timeout => ( is => "ro", isa => "Int", default => $EXECUTE_TIMEOUT );

=head2 connect_timeout : Int

Connect timeout in micro seconds..

Default: 5_000_000 (5 seconds)

=cut

has connect_timeout => ( is => "ro", isa => "Int", default => $CONNECT_TIMEOUT );

=head2 transaction_recovery : Bool

If enabled: use the "safe_transaction" method or not.

Default: 1

=cut

has transaction_recovery => ( is => "ro", isa => "Bool", default => 1 );


=head1 DATABASE METHODS

=cut

sub BUILD {
    my ( $self ) = @_;
    $self->connect;
    return;
}


=head2 search_handle

See L<Mail::Decency::Helper::Database::search>

=cut

sub search_handle {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $args_ref ||= {};
    
    my %limit = ();
    $limit{ limit }   = $args_ref->{ limit }  if defined $args_ref->{ limit };
    $limit{ skip }    = $args_ref->{ offset } if defined $args_ref->{ offset };
    $limit{ sort_by } = $self->update_order( $args_ref->{ order } )
        if defined $args_ref->{ order };
    
    $self->read_lock; # accquire semaphore
    $search_ref = $self->update_query( $search_ref );
    
    my ( $cursor ) = $self->safe_transaction(
        $schema => $table => query => [ $search_ref, \%limit ] );
    my @res = $cursor ? $cursor->all : ();
    
    $self->read_unlock; # release semaphore
    return wantarray ? @res : \@res;
}


=head2 search_read

See L<Mail::Decency::Helper::Database::search_read>

=cut

sub search_read {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $search_ref = $self->update_query( $search_ref );
    my %limit = ();
    $limit{ limit } = $args_ref->{ limit } if defined $args_ref->{ limit };
    $limit{ skip }  = $args_ref->{ offset } if defined $args_ref->{ offset };
    my ( $handle ) = $self->safe_transaction(
        $schema => $table => query => [ $search_ref, \%limit ] );
    return ( $handle, 'next' );
}

=head2 count

See L<Mail::Decency::Helper::Database::count>

=cut

sub count {
    my ( $self, $schema, $table, $search_ref ) = @_;
    $search_ref = $self->update_query( $search_ref );
    my ( $count ) = $self->safe_transaction( $schema => $table => count => [ $search_ref ] );
    return $count;
}


=head2 get_handle

See L<Mail::Decency::Helper::Database::get>

=cut

sub get_handle {
    my ( $self, $schema, $table, $search_ref, $no_lock ) = @_;
    $no_lock ||= 0;
    $self->read_lock unless $no_lock;
    $search_ref = $self->update_query( $search_ref );
    my ( $ref ) = $self->safe_transaction( $schema => $table => find_one => [ $search_ref ] );
    $self->read_unlock unless $no_lock;
    return $self->parse_data( $ref );
}


=head2 set_handle

See L<Mail::Decency::Helper::Database::set>

=cut

sub set_handle {
    my ( $self, $schema, $table, $search_ref, $data_ref, $args_ref ) = @_;
    $args_ref ||= {};
    $self->write_lock; # accquire semaphore
    $search_ref = $self->update_query( $search_ref );
    $data_ref   = $self->update_data( $data_ref );
    delete $data_ref->{ _id } if defined $data_ref->{ _id };
    
    my $res;
    
    if ( $args_ref->{ update_all } ) {
        $self->safe_transaction( $schema => $table => update => [
            $search_ref,
            { '$set' => $data_ref },
            { multiple => 1 }
        ] );
    }
    else {
        my ( $item )
            = $self->safe_transaction( $schema => $table => find_one => [ $search_ref ] );
        my $search_unique_ref = $item
            ? $self->get_unique_key_query( $schema => $table => $item )
            : undef
        ;
        my ( $meth, @args ) = $search_unique_ref
            ? ( update => $search_unique_ref, { '$set' => $data_ref }, { upsert => 1 } )
            : ( insert => { %$search_ref, %$data_ref } )
        ;
        ( $res ) = $self->safe_transaction( $schema => $table => $meth => \@args );
    }
    
    $self->write_unlock; # release semaphore
    return $res;
}


=head2 increment

See L<Mail::Decency::Helper::Database::increment>

=cut


sub increment {
    my ( $self, $schema, $table, $search_ref, $args_ref ) = @_;
    $args_ref ||= {};
    my $key         = $args_ref->{ key } || 'data';
    my $amount      = $args_ref->{ amount } || 1;
    my $last_update = $args_ref->{ last_update } || 0;
    $last_update = 'last_update' if $last_update == 1;
    
    $self->usr_lock; # 
    
    my $ref = $self->get_handle( $schema => $table => $search_ref );
    $ref ||= { $key => 0 };
    $ref->{ $key } += $amount;
    $ref->{ $last_update } = time() if $last_update;
    $self->set( $schema => $table => $search_ref => $ref );
    #update({'x' => 3}, {'$inc' => {'count' => -1} }, {"upsert" => 1, "multiple" => 1});
    
    $self->usr_unlock; #
    
    return $ref->{ $key };
}



=head2 distinct

See L<Mail::Decency::Helper::Database::distinct>

=cut

sub distinct {
    my ( $self, $schema, $table, $search_ref, $key ) = @_;
    $key ||= 'data';
    $search_ref = $self->update_query( $search_ref );
    
    my $cmd = new Tie::IxHash( distinct => "${schema}_${table}" );
    $cmd->Push( key   => $key );
    $cmd->Push( query => $search_ref );
    
    $self->read_lock; # accquire exclusive semaphore
    my ( $res ) = $self->db->run_command( $cmd );
    $self->read_unlock; # release exclusive semaphore
    
    if ( $res && $res->{ ok } ) {
        my @values = grep { defined } @{ $res->{ values } };
        return wantarray ? @values : \@values;
    }
    return ;
}



=head2 remove_handle

See L<Mail::Decency::Helper::Database::remove>

=cut

sub remove_handle {
    my ( $self, $schema, $table, $search_ref ) = @_;
    $self->write_lock; # accquire semaphore
    $search_ref = $self->update_query( $search_ref );
    my ( $res ) = $self->safe_transaction( $schema => $table => remove => [ $search_ref ] );
    $self->write_unlock; # release semaphore
    return $res;
}


=head1 ENVIRONMENT METHODS

=head2 connect

Try to connect to mongod

=cut

sub connect {
    my ( $self ) = @_;
    
    # assure connection canceled
    undef $self->{ db };
    
    # init connetion
    my %connect = (
        auto_reconnect => 1,
    );
    
    # extract hosts
    
        # multiple hosts
    if ( $self->host =~ /,/ ) {
        my ( $left, $right ) = split( /\s*,\s*/, $self->host, 2 );
        my ( $pleft, $pright ) = split( /\s*,\s*/, $self->port, 2 );
        $pright ||= $pleft;
        $connect{ host } = 'mongodb://'. join( ',',
            join( ':', $left, $pleft ),
            join( ':', $right, $pright ),
        );
    }
    
        # single host
    else {
        my $host = $self->host || 'localhost';
        my $port = $self->port || '27017';
        $connect{ host } = 'mongodb://'. join( ':', $host, $port );
    }
    
    # using auth ?
    if ( $self->use_auth ) {
        $connect{ username } = $self->user;
        $connect{ password } = $self->pass if $self->pass;
        $connect{ db_name }  = $self->database;
    }
    
    # debug output of connection string
    my %dbg_connect = %connect;
    $dbg_connect{ password } = '***' if $dbg_connect{ password };
    my $connect_string = join( ' / ', map {
        my $v = defined $dbg_connect{ $_ } ? "'$dbg_connect{ $_ }'" : '-';
        "$_: $v";
    } qw/ host db_name username password / );
    
    # build connection
    my $connect_timeout = $self->connect_timeout;
    eval {
        local $SIG{ ALRM } = sub {
            die sprintf( 'Connect timeout after %.2f seconds', $connect_timeout / 1_000_000 ). "\n";
        };
        ualarm( $connect_timeout );
        $self->{ db } = MongoDB::Connection->new( %connect )->get_database( $self->database );
        alarm( 0 );
        
        $self->logger
            and $self->logger->debug1( "Successfull connected to MongoDB [$connect_string]" );
    };
    if ( $@ ) {
        $self->logger
            and $self->logger->error( "Connection to mongodb failed with [$connect_string]: $@" ); 
        croak "Connection to mongodb failed [$connect_string]: $@";
    }
}


=head2 disconnect

Close connection to MongoDB

=cut

sub disconnect {
    delete shift->{ db };
}


=head2 stat_print

@TODO@

=cut

sub stat_print {
    my ( $self ) = @_;
    print "TODO\n";
}

=head2 ping

Pings MongoDB Server, check wheter connect possible or not

=cut

sub ping_handle {
    my ( $self, $schema, $table ) = @_;
    
    eval {
        my $col = $self->db->get_collection( "${schema}_${table}" );
    };
    
    # do not bother about errors.. just log them. Collections will be created on-the-fly
    if ( $@ ) {
        $self->logger->debug0( "Collection '${$schema}_${table}' not existing, yet.. no harm, should be created automatically. Response: $@" );
    }
    
    # always good
    return 1;
}


=head2 setup

Create database

setup indices

=cut

sub setup_handle {
    my ( $self, $schema, $table, $columns_ref, $execute ) = @_;
    
    if ( $execute ) {
        
        if ( defined $columns_ref->{ -unique } ) {
            my $unique = Tie::IxHash->new( map { ( $_ => 1 ) } @{ $columns_ref->{ -unique } } );
            $self->db->get_collection( "${schema}_${table}" )->ensure_index( $unique, { unique => 1 } );
        }
        
        if ( defined $columns_ref->{ -index } ) {
            my @index = @{ $columns_ref->{ -index } };
            if ( ref( $index[0] ) ) {
                foreach my $idx_ref( @index ) {
                    my $idx = Tie::IxHash->new( map { ( $_ => 1 ) } @$idx_ref );
                    $self->db->get_collection( "${schema}_${table}" )->ensure_index( $idx );
                }
            }
            else {
                my $idx = Tie::IxHash->new( map { ( $_ => 1 ) } @{ $columns_ref->{ -index } } );
                $self->db->get_collection( "${schema}_${table}" )->ensure_index( $idx );
            }
        }
    }
    
    else {
        print "-- MongoDB does no require create statements\n";
    }
    
    return 1;
}


=head2 update_query

Updates query to use MongoDB operators instead of generalized.. eg '$gt' instead of '>' and so on.

    # binary ops
    { col1 => { '>' => 123 } } => { col1 => { '$gt' => 123 } }
    
    # array op
    { col2 => [ 1, 2, 3, 4 ] } => { col2 => { '$in' => [ 1, 2, 3, 4 ] } }
    
    # wildcard op
    { col2 => 'some word*' } => { col2 => { '$in' => qr/(?-xism:^some\ word)/ } }

=cut

sub update_query {
    my ( $self, $ref ) = @_;
    $ref ||= {};
    
    my %op_match = (
        '>'  => '$gt',
        '<'  => '$lt',
        '>=' => '$gte',
        '<=' => '$lte',
        '!=' => '$ne',
    );
    while( my ( $k, $v ) = each %$ref ) {
        my $type = ref( $v );
        next unless $type || $v; # ignore empty / undefined scalar
        
        # from hash -> transform operators
        if ( $type eq 'HASH' ) {
            foreach my $op( keys %$v ) {
                $v->{ $op_match{ $op } } = delete $v->{ $op }
                    if defined $op_match{ $op };
            }
        }
        
        # from array -> use '$in' operator
        elsif ( $type eq 'ARRAY' ) {
            $ref->{ $k } = { '$in' => delete $ref->{ $k } };
        }
        
        # scalar with tailing wildcard "*" -> transform to regex
        elsif ( ! $type && $v =~ /^(.+?)(?<!\\)\*$/ ) {
            $v = $1;
            $ref->{ $k } = qr/^\Q$v\E/;
        }
    }
    
    
    return $ref;
}


=head2 update_order

Bulds Tie::IxHash with MongoDB compatible order

    { col1 => 'asc', col2 => 'desc' }
    => bless( { col1 => 1, col2 => -1 }, 'Tie::IxHash' )

=cut

sub update_order {
    my ( $self, $order_ref ) = @_;
    
    my $order_sorted = Tie::IxHash->new();
    foreach my $ref ( @$order_ref ) {
        $order_sorted->Push( $ref->{ col } => $ref->{ dir } =~ /^asc/i ? 1 : -1 );
    }
    
    return $order_sorted;
}

=head2 check_table

=cut

sub check_table {
    my ( $self, $schema, $table, $table_ref, $update ) = @_;
    my $collection = $self->db->get_collection( "${schema}_${table}" );
    if ( $collection ) {
        my @check = ();
        push @check, [
            'UNIQUE:'. join( ':', sort @{ $table_ref->{ -unique } } ),
            $table_ref->{ -unique }
        ] if defined $table_ref->{ -unique };
        push @check, [
            'INDEX:'. join( ':', sort @{ $table_ref->{ -index } } ),
            $table_ref->{ -index }
        ] if defined $table_ref->{ -index };
        my %required = map { ( $_->[0] => $_->[1] ) } @check;
        
        my ( $missing_ref, $obsolete_ref ) = $self->_get_index_list( $collection, \%required );
        my @errors;
        if ( $update ) {
            foreach my $req( keys %$missing_ref ) {
                my @create = ( { map {
                    ( $_ => 1 )
                } @{ $missing_ref->{ $req } } }, {
                    unique => index( $req, 'UNIQUE:' ) == 0 ? 1 : 0
                } );
                $ENV{ DECENCY_LOG_LEVEL } > 2 && print "DBG> Try create index '$req' on $schema / $table\n";
                my @res = $collection->ensure_index( @create );
                if ( my $err = $self->db->last_error ) {
                    push @errors, $err->{ err };
                }
            }
            
            foreach my $seen( keys %$obsolete_ref ) {
                $ENV{ DECENCY_LOG_LEVEL } > 2 && print "DBG> Try drop index '$obsolete_ref->{ $seen }' from $schema / $table\n";
                $collection->drop_index( $obsolete_ref->{ $seen } );
                if ( my $err = $self->db->last_error ) {
                    push @errors, $err->{ err };
                }
            }
            
            ( $missing_ref, $obsolete_ref ) = $self->_get_index_list( $collection, \%required );
        }
        
        return ( ( scalar( keys %$missing_ref ) + scalar( keys %$obsolete_ref ) ) == 0,
            [ keys %$missing_ref ], [ keys %$obsolete_ref ], \@errors
        );
    }
    
    return ( 0 );
}

=head2 _get_index_list

=cut

sub _get_index_list {
    my ( $self, $collection, $required_ref ) = @_;
    my ( %missing, %obsolete );
    %missing = %$required_ref;
    my @indexes = $collection->get_indexes();
    foreach my $ref( @indexes ) {
        next if $ref->{ name } eq '_id_';
        my @name = ();
        push @name, ( defined $ref->{ unique } && $ref->{ unique } ? 'UNIQUE': 'INDEX' );
        push @name, sort keys %{ $ref->{ key } };
        my $name = join( ':', @name );
        if ( defined $missing{ $name } ) {
            delete $missing{ $name };
        }
        else {
            $obsolete{ $name } = $ref->{ name };
        }
    }
    
    return ( \%missing, \%obsolete );
}


=head2 safe_transaction

The current MongoDB driver for perl does not handle auto-reconnects very well.
Also timeouts on slow or high load machines can mess things terrible up.
Therefore this methods tries to compensate those cases by smart error handlign.

Handlede Errors:

=over

=item * "missed the response we wanted"

The "missed response" error can be handled in most cases by firing the same request some mili-seconds later.

=item * lost connection / execution timeout

In this case, only a forced disconnect / can help, as far as i experienced

=item * anything else

In this case, the child process will die

=back

=cut

sub safe_transaction {
    my ( $self, $schema, $table, $method, $args_ref, $counter ) = @_;
    $counter ||= 0;
    
    my @res;
    
    # if mongodb was restarted, this will throw an error
    my $execute_timeout = $self->execute_timeout;
    eval {
        local $SIG{ ALRM } = sub {
            die sprintf( 'Process timeout after %.2f seconds', $execute_timeout / 1_000_000 ). "\n";
        };
        ualarm( $execute_timeout );
        @res = $self->db->get_collection( "${schema}_${table}" )->$method( @$args_ref );
        alarm( 0 );
    };
    my $process_error = $@;
    
    # return results ?
    return @res unless $process_error;
    
    # error handlign disabled -> do no force!
    die $process_error unless $self->transaction_recovery;
    
    # missed reponse -> try aain
    if ( $process_error =~ /missed the response we wanted/ && $counter < 2 ) {
        usleep( 5_000 ); # wait 5ms
        return $self->safe_transaction( $schema, $table, $method, $args_ref, $counter + 1 );
    }
    
    # Not connected or timeout
    elsif ( $process_error =~ /not connected|Process timeout/ ) {
        
        # asure last connection closed
        eval { undef $self->{ db }; 1 }
            or $self->logger->error( "Error closing obsolete connection to MongoDB: '$@'" );
        
        # try connect
        eval { $self->connect; };
        
        # mongo db probably down:
        if ( $@ ) {
            undef $self->{ db };
            $self->logger->error( "Could not re-connect to MongoDB: '$@'" );
            croak "Could not re-connect to MongoDB: '$@'";
        }
        
        $self->logger->info( "Successfully reconnected to MongoDB" );
        
        # fetch again
        @res = $self->db->get_collection( "${schema}_${table}" )->$method( @$args_ref );
    }
    
    # any other error -> kill this process
    elsif ( $process_error ) {
        undef $self->{ db };
        $self->logger
            and $self->logger->error( "Unhandled MongoDB problem after process timeout: '$process_error'" );
        croak "Unhandled MongoDB problem after process timeout: '$process_error'";
    }
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

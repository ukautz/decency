package Mail::Decency::Doorman::Greylist;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
    Mail::Decency::Doorman::Model::Greylist
/;
with qw/
    Mail::Decency::Core::Meta::Database
    Mail::Decency::Core::Meta::Maintenance
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Mail::Decency::Helper::IP qw/ is_local_host /;
use Mail::Decency::Helper::IntervalParse qw/ interval_to_int /;

use Data::Dumper;
use YAML;

=head1 NAME

Mail::Decency::Doorman::Greylist


=head1 DESCRIPTION

A greylist implementation (http://www.greylisting.org/) for decency.

=head1 CONFIG

    ---
    
    disable: 0
    timeout: 30
    
    # interval in seconds until a sender is allowed to re-send
    #   and pass (seconds)
    min_interval: 60
    
    # after this amount of hits, the sender ADDRES will be acceppeted
    #   for the whole recipient DOMAIN
    recipient_domain_threshold: 5
    
    # after this amount of hits, the sender DOMAIN will be acceppeted
    #   for the whole recipient DOMAIN
    sender_domain_threshold: 10
    
    # period of time after which each triplet (in all tables)
    #   will become obsolete (if not seen)
    #   default: 90d
    maintenance_ttl: 90d 
    
    # wheter ignore IPs which will improve contacts with big freemailers (which
    #   have multiple send servers and it can therefore multiple tries until
    #   the second try from the same IP occurs). requires SPF and/or Association
    #   module run before
    ignore_ip_if_validated: 1
    
    # If enable, mails from localhost (127./8, ::1) will be handled as well
    handle_localhost: 1



=head1 CLASS ATTRIBUTES


=head2 recipient_domain_threshold : Int

Amount of hits in the regular triplet database, after which the sender ADDRESS is allowed to send to any recipient of the recipient domain.

Default: 5

-1 disables this feature

=cut

has recipient_domain_threshold => ( is => 'rw', isa => 'Int', default => 5 );


=head2 sender_domain_threshold : Int

Amount of hits in the regular triplet database, after which the sender DOMAIN is allowed to send to any recipient of the recipient domain.

Default: 10

-1 disables this feature

=cut

has sender_domain_threshold => ( is => 'rw', isa => 'Int', default => 10 );

=head2 min_interval : Int

Min interval the sender has to wait until the re-send mail is accepted.

Default: 10m (10 minutes) 

=cut

has min_interval => ( is => 'rw', isa => 'Int | Str', default => '10m', trigger => sub {
    my ( $self, $interval ) = @_;
    $self->{ min_interval } = interval_to_int( $interval );
} );

=head2 reject_message : Str

Message for greylisted rejection.

Default: "Greylisted - Patience, young jedi"

=cut

has reject_message  => ( is => 'rw', isa => 'Str', default => "Greylisted - Patience, young jedi" );


=head2 maintenance_ttl : Int | Str

Modify default maintenance TTL to 90 days ..

=cut

has maintenance_ttl => ( is => 'rw', isa => 'Int | Str', default => '90d', trigger => sub {
    my ( $self, $period ) = @_;
    $self->{ maintenance_ttl } = interval_to_int( $period );
} );


=head2 ignore_ip_if_validated : Bool

Bool.. if enabled and the Association and/or SPF module runs beforehand and determines a valid state (SPF OK, Association found) the IP will be stored as "IGNOREVALID"

Default: 1

=cut

has ignore_ip_if_validated => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 handle_localhost : Bool

See L<Mail::Decency::Doorman::Core>

This defaults to 1, cause it does not harm

=cut

has handle_localhost => ( is => 'rw', isa => 'Bool', default => 1 );



has _cur_ip => ( is => 'rw', isa => 'Str' );

=head1 METHODS


=head2 init

=cut 

sub init {
    my ( $self ) = @_;
    
    # min interval before re-send is considered ok
    foreach my $k( qw/
        recipient_domain_threshold
        sender_domain_threshold
        reject_message
        maintenance_ttl
        min_interval
        ignore_ip_if_validated
    / ) {
        $self->$k( $self->config->{ $k } )
            if defined $self->config->{ $k };
    }
    
    return;
}


=head2 handle

=cut

sub handle {
    my ( $self ) = @_;
    
    # greylist requires full sender / recipients (not for auto-replies with no such)
    return if
        ! $self->from || ! $self->from_domain
        || ! $self->to || ! $self->to_domain
    ;
    
    $self->_cur_ip( $self->ignore_ip_if_validated && ( $self->has_flag( 'spf_pass' ) || $self->has_flag( 'assoc_ok' ) )
        ? 'IGNOREVALID'
        : $self->ip
    );
    
    #
    # CACHES
    #
    
    my ( @caches, %name ) = ();
    
    # sender domain
    #   domain -> ip -> domain
    push @caches, $name{ sender } = "Greylist-S-". join( "-",
        $self->from_domain,
        $self->ip,
        $self->to_domain,
    );
    
    # recipient domain
    #  address -> ip -> domain
    push @caches, $name{ recipient } = "Greylist-R-". join( "-",
        $self->from,
        $self->ip,
        $self->to_domain,
    );
    
    # regular
    #   address -> ip -> address
    push @caches, $name{ address } = "Greylist-A-". join( "-",
        $self->from,
        $self->ip,
        $self->to,
    );
    
    #
    # CHECK CACHES
    #
    my $pass = 0;
    my $round = 0;
    foreach my $cache( @caches ) {
        my $cached = $self->cache->get( $cache );
        
        # found cached ..
        if ( $cached && ( $cached eq 'OK' || $cached + $self->min_interval <= time() ) ) {
            $pass++;
            
            # if found is address -> increment both: recipient and sender tables
            if ( $round == 2 ) {
                $self->_inc_recipient( \%name );
                $self->_inc_sender( \%name );
            }
            elsif ( $round == 1 ) {
                $self->_inc_sender( \%name );
            }
            last;
        }
        $round++;
    }
    
    # not from cache -> try from database
    unless ( $pass ) {
        $pass = $self->update_pass( \%name );
    }
    
    # not passing ?
    unless ( $pass ) {
        
        # greylist message shall be the only message
        $self->session->message( [ $self->reject_message ] );
        
        # and reject temporary ..
        $self->go_final_state( 450 );
    }
}


=head2 update_pass

Add counters to pass databases

=cut

sub update_pass {
    my ( $self, $caches_ref ) = @_;
    
    # check wheter known, bigger then zero and time ok
    my $address_ok = 0;
    
    # check in recipient
    foreach my $meth( qw/ _check_sender _check_recipient _check_address / ) {
        my $res = $self->$meth( $caches_ref );
        if ( $res != 0 ) {
            $address_ok = $res;
            last;
        }
    }
    
    # -1 : sender is in grace period, no increments
    return 0 if $address_ok == -1;
    
    # increment databases
    $self->$_( $caches_ref )
        for qw/ _inc_address _inc_recipient _inc_sender /;
    
    # return result
    return $address_ok;
}


=head2 _check_address

=cut

sub _check_address {
    my ( $self ) = @_;
    
    # get address entry
    my $address_ref = $self->database->get( greylist => address => {
        from_address => $self->from,
        ip           => $self->ip,
        to_address   => $self->to,
    } );
    
    if ( $address_ref && (
        ( $address_ref->{ data } == 1 && $address_ref->{ last_update } + $self->min_interval <= time() )
        || $address_ref->{ data } > 1
    ) ) {
        return 1;
    }
    elsif ( $address_ref ) {
        return -1;
    }
    return 0;
}

=head2 _check_recipient

=cut

sub _check_recipient {
    my ( $self, $caches_ref ) = @_;
    return 0 unless $self->recipient_domain_threshold > -1;
    
    # get recipient entry
    my $recipient_ref = $self->database->get( greylist => recipient => {
        from_address => $self->from,
        ip           => $self->ip,
        to_domain    => $self->to_domain,
    }, {
        last_update => 1
    } );
    
    if ( $recipient_ref && $recipient_ref->{ data } >= $self->recipient_domain_threshold ) {
        $self->cache->set( $caches_ref->{ recipient } => 'OK' );
        return 1;
    }
    return 0;
}

=head2 _check_sender

=cut

sub _check_sender {
    my ( $self, $caches_ref ) = @_;
    return 0 unless $self->sender_domain_threshold > -1;
    
    # get sender entry
    my $sender_ref = $self->database->get( greylist => sender => {
        from_domain => $self->from_domain,
        ip          => $self->ip,
        to_domain   => $self->to_domain,
    }, {
        last_update => 1
    } );
    
    if ( $sender_ref && $sender_ref->{ data } >= $self->sender_domain_threshold ) {
        $self->cache->set( $caches_ref->{ sender } => 'OK' );
        return 1;
    }
    return 0;
}

=head2 _inc_address

=cut

sub _inc_address {
    my ( $self, $caches_ref ) = @_;
    
    # increment address database
    my $amount_address = $self->database->increment( greylist => address => {
        from_address => $self->from,
        ip           => $self->ip,
        to_address   => $self->to,
    }, {
        last_update => 1
    } );
    $self->cache->set( $caches_ref->{ address } => $amount_address > 1 ? 'OK' : time() );
}


=head2 _inc_recipient

=cut

sub _inc_recipient {
    my ( $self, $caches_ref ) = @_;
    return unless $self->recipient_domain_threshold > -1;
    return if $self->cache->get( $caches_ref->{ recipient } );
    
    # increment recipient database
    my $amount_recipient = $self->database->increment( greylist => recipient => {
        from_address => $self->from,
        ip           => $self->ip,
        to_domain    => $self->to_domain,
    }, {
        last_update => 1
    } );
    $self->cache->set( $caches_ref->{ recipient } => 'OK' )
        if $amount_recipient >= $self->recipient_domain_threshold;
}


=head2 _inc_sender

=cut

sub _inc_sender {
    my ( $self, $caches_ref ) = @_;
    return unless $self->sender_domain_threshold > -1;
    return if $self->cache->get( $caches_ref->{ sender } );
    
    # increment sender database
    my $amount_sender = $self->database->increment( greylist => sender => {
        from_domain => $self->from_domain,
        ip          => $self->ip,
        to_domain   => $self->to_domain,
    }, {
        last_update => 1
    } );
    $self->cache->set( $caches_ref->{ sender } => 'OK' )
        if $amount_sender >= $self->sender_domain_threshold;
}

=head2 maintenance

Called by Doorman in maintenance mode. Cleans up obsolete entries in greylist databsae

=cut

sub maintenance {
    my ( $self ) = @_;
    my $obsolete_time = DateTime->now( time_zone => 'local' )->epoch - $self->maintenance_ttl;
    while ( my ( $schema, $tables_ref ) = each %{ $self->schema_definition } ) {
        while ( my ( $table, $ref ) = each %{ $tables_ref } ) {
            my $obsolete = $self->database->count( $schema => $table => {
                last_seen => {
                    '<' => $obsolete_time
                }
            } );
            $self->logger->debug1( sprintf( 'Remove %d entries from %s (obsolet all < %d seconds)', $obsolete, "${schema}_${table}", $self->maintenance_ttl ) );
            $self->database->remove( $schema => $table => {
                last_seen => {
                    '<' => $obsolete_time
                }
            } ) unless $ENV{ DRY_RUN };
        }
    }
}

=head2 ip

Overwrite the IP method to return the _cur_ip (possible: IGNOREVALID)

=cut

sub ip {
    my ( $self ) = @_;
    return $self->_cur_ip || $self->session->ip;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

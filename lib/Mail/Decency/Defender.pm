package Mail::Decency::Defender;

=head1 NAME

Mail::Decency::Defender - milter or prequeue filter server

=head1 DESCRIPTION

This server combines Doorman and Detective in a single server which can be implemented either as a milter or via the postfix prequeue filter technology.

=head1 SYNOPSIS


=cut

use Mouse;
extends qw/
    Mail::Decency::Core::Server
/;
use Mail::Decency::Core::POEForking::PreQueueSMTP;
use Mail::Decency::Detective;
use Mail::Decency::Doorman;
use Scalar::Util qw/ weaken /;
use Net::DNS;
use File::Temp qw/ tempfile /;

=head1 CLASS ATTRIBUTES

=head2 doorman

Handler to Detective instance

=cut

has doorman => ( isa => 'Mail::Decency::Doorman', is => 'rw', predicate => 'has_doorman' );

=head2 detective

Handler to Detective instance

=cut

has detective => ( isa => 'Mail::Decency::Detective', is => 'rw', predicate => 'has_detective' );

=head2 mode

Handler to Detective instance

=cut

has mode => ( isa => 'Str', is => 'ro', default => 'prequeue' );

=head2 pmilter



=cut

has pmilter => ( isa => 'Mail::Decency::Core::MilterServer', is => 'ro' );

=head1 METHODS

=head2 init

Init Defender instance with all sub instances (Detective and/or Doorman).

=cut

sub init {
    my ( $self ) = @_;
    
    # init name
    $self->name( "defender" );
    $self->init_logger();
    # $self->init_cache();
    # $self->init_database();
    
    # init Detective instance, so we can use content filtering
    if ( defined $self->config->{ doorman } ) {
        my %config = (
            ( map {
                ( $_ => $self->can( $_ ) && $self->$_ ? $self->$_ : $self->config->{ $_ } )
            } qw/ reporting database cache logging stats / ),
            %{ $self->config->{ doorman } }
        );
        $self->doorman( Mail::Decency::Doorman->new(
            config => \%config, config_dir => $self->config_dir ) );
        $self->doorman->_encapsulated( 1 );
        $self->doorman->init;
    }
    
    # init Detective instance, so we can use content filtering
    if ( defined $self->config->{ detective } ) {
        my %config = (
            ( map {
                ( $_ => $self->config->{ $_ } )
            } qw/ reporting database cache logging stats / ),
            %{ $self->config->{ detective } }
        );
        $self->detective( Mail::Decency::Detective->new(
            config => \%config, config_dir => $self->config_dir ) );
        $self->detective->_encapsulated( 1 );
        $self->detective->init;
    }
    
    $self->{ mode } = $self->config->{ mode } || 'prequeue';
    die "Mode $self->{ mode } not allowed, use either 'prequeue' or 'milter'\n"
        unless $self->mode =~ /^(?:prequeue|milter)$/;
}


=head2 run

Start and run the server via POE::Kernel->run

=cut

sub run {
    my ( $self ) = @_;
    $self->start();
    
    if ( $self->mode eq 'prequeue' ) {
        POE::Kernel->run;
    }
    else {
        $self->pmilter->main;
    }
}

sub start {
    my ( $self ) = @_;
    $self->set_locker( 'default' );
    $self->set_locker( 'database' );
    $self->set_locker( 'reporting' )
        if $self->config->{ reporting };
    
    if ( $self->mode eq 'prequeue' ) {
        Mail::Decency::Core::POEForking::PreQueueSMTP->new( $self );
    }
    else {
        eval 'use Sendmail::PMilter; use Mail::Decency::Core::MilterServer; 1;'
            or die "Could not load Sendmail::PMilter: $@\n";
        $self->{ pmilter } = Mail::Decency::Core::MilterServer->new( parent => $self );
    }
}

sub handle_safe {
    my ( $self, $type, $ref ) = @_;
    
    #
    # DOORMAN
    #
    if ( $type eq 'envelope' && $self->has_doorman ) {
        
        # reverse lookup client
        my $reverse_client_name = $ref->{ client_reverse_addr } //= '';
        if ( defined $ref->{ client_addr } && ! $reverse_client_name ) {
            my $r = Net::DNS::Resolver->new;
            my $q = $r->query( $ref->{ client_addr }, 'PTR' );
            if ( $q ) {
                ( $reverse_client_name ) = map { $_->ptrdname } $q->answer;
            }
        }
        
        my %attrs = (
            request             => 'smtpd_access_policy',
            protocol_state      => 'RCPT',
            protocol_name       => 'SMTP',
            helo_name           => $ref->{ client_helo },
            sender              => $ref->{ mail_from },
            recipient           => $ref->{ rcpt_to },
            client_address      => $ref->{ client_addr },
            client_name         => $ref->{ client_name },
            reverse_client_name => $reverse_client_name,
            size                => 0,
            queue_id            => $ref->{ queue_id } || '',
            
            sasl_username       => $ref->{ sasl_user } || '',
            sasl_method         => $ref->{ sasl_method } || '',
            sasl_sender         => '',  # <<< Not supported
            
            ccert_subject       => '',  # <<< Not supported
            ccert_issuer        => '',  # <<< Not supported
            ccert_fingerprint   => '',  # <<< Not supported
            instance            => '',  # <<< Not supported
        );
        
        # pipe through Doorman instance
        my $res = $self->doorman->handle_safe( \%attrs );
        if ( $res->{ action } =~ /^(PREPEND|OK|DUNNO)(?: (.+?))?$/ ) {
            print "*** DOORMAN RETURN OK\n";
            return ( 1, "" );
        }
        else {
            print "*** DOORMAN RETURN REJECT (action=$res->{ action })\n";
            my ( $mode, $msg ) = split( / /, $res->{ action }, 2 );
            return ( 0, $res->{ action } );
        }
    }
    
    #
    # DETECTIVE
    #
    elsif ( $type eq 'data' && $self->has_detective ) {
        
        # pipe through Detective instance
        my @r = $self->detective->handle_safe( $ref );
        
        return @r;
    }
    
    return ( 1, "" );
}


sub setup {
    my ( $self ) = @_;
    $self->doorman->setup if $self->has_doorman;
    $self->detective->setup if $self->has_detective;
    print "****\nCall Setup\n******\n";
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

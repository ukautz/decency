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
use Scalar::Util qw/ weaken /;
use Net::DNS;
use File::Temp qw/ tempfile /;
use Time::HiRes qw/ gettimeofday tv_interval /;
use Mail::Decency::Helper::Debug;

=head1 CLASS ATTRIBUTES

=head2 doorman

Handler to Detective instance

=cut

has doorman => ( isa => 'Mail::Decency::Doorman', is => 'rw', predicate => 'has_doorman', weak_ref => 1 );

=head2 detective

Handler to Detective instance

=cut

has detective => ( isa => 'Mail::Decency::Detective', is => 'rw', predicate => 'has_detective', weak_ref => 1 );

=head2 mode

Handler to Detective instance

=cut

has mode => ( isa => 'Str', is => 'ro', default => 'prequeue' );

=head2 pmilter

=cut

has pmilter => ( isa => 'Mail::Decency::Core::MilterServer', is => 'ro', weak_ref => 1 );

=head2 smtp

=cut

has smtp => ( isa => 'Mail::Decency::Core::NetServer::Defender', is => 'ro', weak_ref => 1 );


=head2 enforce_reinject

If enabled, using internal reinjection. Can be used only in milter context

=cut

has enforce_reinject => ( isa => 'Bool', is => 'ro', default => 0 );


=head2 detective_spam_reply : Str

Detective has normally no spam reply, so here it can be set

Default: SPAM detected

=cut

has detective_spam_reply => ( isa => 'Str', is => 'ro', default => 'SPAM detected' );


=head2 detective_virus_reply : Str

Detective has normally no spam reply, so here it can be set

Default: SPAM detected

=cut

has detective_virus_reply => ( isa => 'Str', is => 'ro', default => 'Virus detected' );

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
    
    my $defender_conf_ref = $self->config->{ defender } || {
        #detective_spam_reply => '',
        #detective_virus_reply => '',
        #detective_enforce_reinject => 0,
    };
    
    $self->{ mode } = $self->config->{ mode } || 'prequeue';
    DD::cop_it "Mode $self->{ mode } not allowed, use either 'prequeue' or 'milter'\n"
        unless $self->mode =~ /^(?:prequeue|milter)$/;
    
    # init Detective instance, so we can use content filtering
    if ( defined $self->config->{ doorman } ) {
        eval 'use Mail::Decency::Doorman; 1;'
            or DD::cop_it "Could not load Doorman module: $@\n";
        my %config = (
            ( map {
                ( $_ => $self->can( $_ ) && $self->$_ ? $self->$_ : $self->config->{ $_ } )
            } qw/ reporting database cache logging stats / ),
            %{ $self->config->{ doorman } }
        );
        $self->doorman( Mail::Decency::Doorman->new(
            config => \%config, config_dir => $self->config_dir ) );
        $self->doorman->encapsulated( 1 );
        $self->doorman->encapsulated_server( $self );
        $self->doorman->init;
    }
    
    # init Detective instance, so we can use content filtering
    if ( defined $self->config->{ detective } ) {
        eval 'use Mail::Decency::Detective; 1;'
            or DD::cop_it "Could not load Detective module: $@\n";
        
        my %config = (
            ( map {
                ( $_ => $self->config->{ $_ } )
            } qw/ reporting database cache logging stats / ),
            %{ $self->config->{ detective } }
        );
        $self->detective( Mail::Decency::Detective->new(
            config => \%config, config_dir => $self->config_dir ) );
        $self->detective->encapsulated( 1 );
        $self->detective->encapsulated_server( $self );
        $self->detective->init;
        
        # in milter mode: enforce reinjection
        if ( $defender_conf_ref->{ detective_enforce_reinject } ) {
            DD::cop_it "Cannot enabled 'enforce_reinject' in preqeue-mode. This is only available in milter-mode!"
                if $self->mode ne 'milter';
            $self->enforce_reinject( 1 );
        }
        
        # additional detective stuff
        foreach my $key( qw/ detective_spam_reply detective_virus_reply / ) {
            $self->$key( $defender_conf_ref->{ $key } )
                if defined $defender_conf_ref->{ $key };
        }
        
        # check required reinjection
        DD::cop_it "Require reinjections if prequeue-mode is used or detective_enforce_reinject is set in milter-mode. Provide 'reinject' in detective section\n"
            if ! $self->detective->can_reinject
            && ( $self->mode() eq 'prequeue' || $self->enforce_reinject ) 
        ;
    }
    
}


=head2 run

Run the Defender server

=cut

sub run {
    my ( $self ) = @_;
    
    $self->set_locker( 'default' );
    $self->set_locker( 'database' );
    $self->set_locker( 'reporting' )
        if $self->config->{ reporting };
    
    $self->logger->debug1( sprintf( 'Start Defender in %s mode', $self->mode ) );
    
    if ( $self->mode eq 'prequeue' ) {
        eval 'use Mail::Decency::Core::NetServer::Defender; 1;'
            or DD::cop_it "Could not load Mail::Decency::Core::NetServer::Defender: $@\n";
        $self->{ smtp } = Mail::Decency::Core::NetServer::Defender->new( {
            defender => $self
        } );
        
        if ( $self->has_detective ) {
            # update session cache from doorman and disable reinject
            $self->detective->register_hook( session_init => sub {
                my ( $server ) = @_;
                #$server->session->disable_reinject( 1 )
            } );
        }
        
        my $instances = $self->config->{ server }->{ instances } > 1
            ? $self->config->{ server }->{ instances }
            : 2;
        $self->smtp->run(
            port              => $self->config->{ server }->{ port },
            host              => $self->config->{ server }->{ host },
            min_servers       => $instances -1,
            max_servers       => $instances +1,
            min_spare_servers => $instances -1,
            max_spare_servers => $instances,
            no_client_stdout  => 1,
            #log_level        => 4,
        );
        
    }
    else {
        eval 'use Sendmail::PMilter; 1;'
            or DD::cop_it "Could not load Sendmail::PMilter: $@\n";
        eval 'use Mail::Decency::Core::MilterServer; 1;'
            or DD::cop_it "Could not load Mail::Decency::Core::MilterServer: $@\n";
        $self->{ pmilter } = Mail::Decency::Core::MilterServer->new( parent => $self );
        
        if ( $self->has_detective ) {
            # update session cache from doorman and disable reinject
            $self->detective->register_hook( session_init => sub {
                my ( $server ) = @_;
                
                # get context
                my $defender = $server->encapsulated_server;
                my $ctx = $defender->pmilter->current_context;
                return unless $ctx;
                
                # for detective -> update cache
                # update doorman
                my $data_ref = $ctx->getpriv() || {};
                if ( defined $data_ref->{ doorman_session_data } ) {
                    $server->session->update_from_doorman_cache(
                        $data_ref->{ doorman_session_data } );
                }
                
                # disable reinject ?
                $server->session->disable_reinject( 1 )
                    unless $defender->enforce_reinject;
                
            } );
        }
        $self->pmilter->main;
    }
}

=head2 handle_safe

Handles data by passing it either to the Doorman or the Detective instance.

=cut

sub handle_safe {
    my ( $self, $type, $ref ) = @_;
    
    my $start = [ gettimeofday() ];
    
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
        my $res = $self->doorman->handle_safe( \%attrs, { return_session_data => 1 } );
        
        $self->logger->debug1( sprintf( 'Time for Doorman: %0.2f', tv_interval( $start, [ gettimeofday() ] ) ) );
        
        # we can go on
        if ( $res->{ action } =~ /^(PREPEND|OK|DUNNO)(?: (.+?))?$/ ) {
            return ( 1, "", $res->{ session_data } );
        }
        
        # this it is .. reject
        else {
            my ( $mode, $msg ) = split( / /, $res->{ action }, 2 );
            return ( 0, $res->{ action } );
        }
    }
    
    #
    # DETECTIVE
    #
    elsif ( $type eq 'data' && $self->has_detective ) {
        
        # pipe through Detective instance
        my @res;
        eval { @res = $self->detective->handle_safe( $ref ); };
        
        $self->logger->debug1( sprintf( 'Time for Detective: %0.2f', tv_interval( $start, [ gettimeofday() ] ) ) );
        
        return @res;
    }
    
    return ( 1, "" );
}


=head2 setup

Setup Doorman and Detective instances. Called after fork.

=cut

sub setup {
    my ( $self ) = @_;
    $self->doorman->setup if $self->has_doorman;
    $self->detective->setup if $self->has_detective;
}


=head2 delegate_meth

Delegates methods to all child servers (Detective, Doorman)

=cut

sub delegate_meth {
    my ( $self, $meth, @args ) = @_;
    my %res;
    foreach my $name( qw/ doorman detective / ) {
        my $can = 'has_'. $name;
        if ( $self->$can ) {
            $res{ $name } = wantarray
                ? [ $self->$name->$meth( @args ) ]
                : scalar $self->$name->$meth( @args )
            ;
        }
    }
    return wantarray ? %res : \%res;
}

=head2 detective_response

Interprets Detective response for handling in Defender context.

=cut

sub detective_response {
    my ( $self, $final_state ) = @_;
    
    my $detective = $self->detective;
    my $enforce_reinject = $self->enforce_reinject;
    
    # when using reinject, discard mail (only important for milter!)
    if ( $enforce_reinject ) {
        return ( 'discard' );
    }
    
    # virus handle
    elsif ( $final_state eq 'virus' && $detective->virus_handle eq 'bounce' ) {
        return ( 'reject', $self->detective_spam_reply );
    }
    
    # spam handle
    elsif ( $final_state eq 'spam' && $detective->spam_handle eq 'bounce' ) {
        return ( 'reject', $self->detective_virus_reply );
    }
    
    # discard handle
    elsif ( 
        ( $final_state eq 'spam' && $detective->spam_handle eq 'delete' )
        || ( $final_state eq 'virus' && $detective->virus_handle eq 'delete' )
    ) {
        return ( 'discard' );
    }
    
    # if not rejected -> accept
    else {
        return ( 'accept' );
    }
    
}


=head2 check_structure

Check database structure. Delegated

=cut

sub check_structure {
    shift->delegate_meth( 'check_structure', @_ );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

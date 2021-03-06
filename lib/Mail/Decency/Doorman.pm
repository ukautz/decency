package Mail::Decency::Doorman;

use Mouse;
extends qw/
    Mail::Decency::Core::Server
/;
with qw/
    Mail::Decency::Core::Stats
    Mail::Decency::Core::ExportImport
    Mail::Decency::Core::DatabaseCreate
    Mail::Decency::Core::Excludes
    Mail::Decency::Core::CustomScoring
    Mail::Decency::Core::Reporting
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use feature qw/ switch /;

use Data::Dumper;
use Scalar::Util qw/ weaken blessed /;
use Time::HiRes qw/ tv_interval gettimeofday /;

use Mail::Decency::Helper::Debug;
use Mail::Decency::Helper::IP qw/ is_local_host /;
use Mail::Decency::Core::NetServer::Doorman;
use Mail::Decency::Core::Exception;
use Mail::Decency::Core::SessionItem::Doorman;
use Mail::Decency::Helper::Config qw/
    merged_config
/;

use constant ALLOWED_RESPONSE_STATES => qr/ \A (?:
    PREPEND |
    DUNNO |
    REJECT |
    OK |
    [12345][0-9][0-9]
) /xms;

=head1 NAME

Mail::Decency::Doorman

=head1 SYNOPSIS

    use Mail::Decency::Doorman;
    
    # run in server mode
    my $doorman = Mail::Decency::Doorman->new( {
        config => '/etc/decency/doorman.yml'
    } );
    $doorman->run;
    
    # run in maintenance mode
    $doorman->maintenance;
    
    # print statistics
    $doorman->print_stats;

=head1 DESCRIPTION

L<http://www.decency-antispam.org/docs/doorman>

=head1 CLASS ATTRIBUTES

See L<Mail::Decency::Doorman::Core>


=head2 spam_threshold : Int

Threshold of spam score before reject ( actual score <= threeshold == spam )

=cut

has spam_threshold => ( is => 'rw', isa => 'Int', default => -100 );

=head2 session : Mail::Decency::Core::SessionItem::Doorman

Instance of L<Mail::Decency::Core::SessionItem::Doorman>

=cut

has session => ( is => 'rw', isa => 'Mail::Decency::Core::SessionItem::Doorman' );

=head2 pass_localhost : Bool

Wheter passing everything from localhost or not. Can also set per module. See the "handle_localhost" attribute in L<Mail::Decency::Doorman::Core>

Most modules have "handle_localhost" disabled per defaukt, so most will ignore anything from localhost, even if this is enabled.

Be careful which module you feed with localhost data..

Default: 1

=cut

has pass_localhost => ( is => 'rw', isa => 'Bool', default => 1 );

=head2 ignore_ips : HashRef[Bool]

Static

=cut

has ignore_ips => ( is => 'rw', isa => 'HashRef[Bool]', default => sub { {} } );

=head2 default_reject_message : Str

Default reject message string (after the SMTP REJECT command .. "REJECT message")

Default: use decency

=cut

has default_reject_message => ( is => 'rw', isa => 'Str', default => "use decency" );


=head2 no_reject_detail : Bool

Wheter pass detailed information of why a particular REJECT has been thrown to the sender or not (not=always the default message)/

Default: 0

=cut

has no_reject_detail => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 no_session_identifier : Bool

Wheter disable appending the session identifier to the reject message or not. This identifier is used in logging and reporting.

Very useful if you disable reject details, but still want to figure out why a mail has been rejected later on.

Default: 0

=cut

has no_session_identifier => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 forward_scoring : Bool

Wheter forward scoring informations after policies or not

Default: 0

=cut

has forward_scoring => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 disable_prepend : Bool

Wheter disabling the prepend of instance information fully (implies forward_scoring=0)

Default: 0

=cut

has disable_prepend => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 forward_sign_key : Str

Path to a file containing a private key for signing forwarded

=cut

has forward_sign_key  => ( is => 'rw', isa => 'Str', predicate => 'has_forward_sign_key', trigger => sub {
    my ( $self, $key_file ) = @_;
    
    # check file
    $key_file = $self->config_dir . "/$key_file"
        if $self->has_config_dir && ! -f $key_file;
    DD::cop_it "Could not access doorman_sign_pub key file '$key_file'".
        ( $self->has_config_dir ? ' (config dir: '. $self->config_dir. ')' : '' ). "\n"
        unless -f $key_file;
    
    # read key
    open my $fh, '<', $key_file
        or DD::cop_it "Cannot open doorman_sign_pub key file for read: $!\n";
    my $key_content = join( "", <$fh> );
    close $fh;
    
    # try load rsa and init private key
    my $load_rsa = eval "use Crypt::OpenSSL::RSA; 1;";
    if ( $load_rsa ) {
        $self->forward_sign_key_priv( Crypt::OpenSSL::RSA->new_private_key( $key_content ) );
    }
    
    # failure in loading -> bye
    else {
        DD::cop_it "Could not load Crypt::OpenSSL::RSA, cannot sign headers! Error: $@\n";
    }
    
    return;
} );

=head2 forward_sign_key_priv : Crypt::OpenSSL::RSA

Instance of L<Crypt::OpenSSL::RSA> representing the forward sign key

=cut

has forward_sign_key_priv => ( is => 'rw', isa => 'Crypt::OpenSSL::RSA' );


=head1 METHODS

=head2 init

Loads Doorman modules, inits caches, inits databases ..

=cut

sub init {
    my ( $self ) = @_;
    
    # init name
    $self->name( "doorman" );
    
    # mark es inited
    $self->init_logger();
}

=head2 setup

=cut

sub setup {
    my ( $self ) = @_;
    return if $self->{ inited } ++;
    
    $self->init_postfix_server();
    $self->init_cache();
    $self->init_database();
    $self->init_reloadable();
    return;
}

=head2 init_reloadable

All configurations here can be reloaded (USR2)

=cut

sub init_reloadable {
    my ( $self ) = @_;
    
    $self->init_server_shared();
    
    # set another default reject message
    $self->default_reject_message( $self->config->{ default_reject_message } )
        if $self->config->{ default_reject_message };
    
    # display always default message and no detail ?
    $self->no_reject_detail( 1 )
        if $self->config->{ no_reject_detail };
    
    # add the session ID to the reject message (for later evaluation) ?
    $self->append_session_identifier( 1 )
        if $self->config->{ append_session_identifier };
    
    # disable local passing ?
    if ( $self->config->{ force_check_local } ) {
        $self->pass_localhost( 0 );
    }
    
    # disable prepending at all ?
    if ( $self->config->{ disable_prepend } ) {
        $self->disable_prepend( 1 );
    }
    
    # prepend scoring info to header ?
    elsif ( $self->config->{ forward_scoring } ) {
        $self->forward_scoring( 1 );
        
        # having sign key ?
        if ( $self->config->{ forward_sign_key } ) {
            $self->forward_sign_key( $self->config->{ forward_sign_key } );
        }
    }
    
    # ignore ips ?
    if ( my $ips_ref = $self->config->{ ignore_ips } ) {
        my %ips = ref( $ips_ref ) eq 'ARRAY'
            ? map { ( $_ => 1 ) } @$ips_ref
            : %$ips_ref
        ;
        $self->ignore_ips( \%ips );
    }
    
    # load all modules
    $self->load_modules();
}



=head2 handle_safe

Returns subref to handlers, called by L<Mail::Decency::Core::POEForking::Postfix>

    # all handlers
    my $handlers_ref = $doorman->get_handlers();
    
    # only the awl handler
    my $handlers_ref = $doorman->get_handlers( qw/ AWL / );

=cut

sub handle_safe {
    my ( $self, $attrs_ref, $args_ref ) = @_;
    $args_ref ||= {
        return_session_data => 0
    };
    
    # don bother with loopback addresses
    return {
        action => 'DUNNO'
    } if ( ! $ENV{ HANDLE_LOCAL_CONNECTIONS }
        && $self->pass_localhost
        && is_local_host( $attrs_ref->{ client_address } )
    );
    
    # start handling-session
    $self->session_init( $attrs_ref );
    
    # start
    my $start_time_ref = [ gettimeofday() ];
    
    # on global ignore list?
    return {
        action => 'DUNNO'
    } if defined $self->ignore_ips->{ $self->session->ip };
    
    # apply all policies
    my $state = 'ongoing';
    foreach my $module( @{ $self->childs } ) {
        
        # get handle (bool) and error (string?)
        ( my $handle, $state, my $err )
            = $self->handle_child( $module, [ $self, $attrs_ref ] );
        
        # no handle
        next unless $handle;
        
        # finish, if session data in a final state
        #last if $self->session->response ne 'DUNNO';
        last if lc( $state ) ne 'ongoing';
    }
    
    # run finish hooks
    ( $state ) = $self->run_hooks( 'finish', [ $state ] );

    # time diff
    # my $run_diff = tv_interval( $start_time_ref, [ gettimeofday() ] );
    # ( $status, $final_code ) = $self->run_hooks( 'finish', [ {
    #     status     => $status,
    #     diff       => $run_diff,
    #     details    => join( ' ## ', @{ $self->session->spam_details } )
    # } ] );
    
    # update server stats ?
    eval {
        $self->update_server_stats( $state )
            if $self->enable_server_stats;
    };
    $self->logger->error( "Error in server stats: $@" ) if $@;

    # write reporting ?
    eval {
        $self->write_report( $state, join( ' ## ',
            @{ $self->session->spam_details } ) )
            if $self->reporting_enabled;
    };
    $self->logger->error( "Error in reporting: $@" ) if $@;
    
    # get session data, if required
    my %session_data = $args_ref->{ return_session_data }
        ? ( session_data => $self->session->for_cache )
        : ();
    ;
    
    # clear info and stash to cache
    my $response = $self->session_cleanup();
    
    # return final answer (REJECT, OK, DUNNO, 4xx, 5xx, ..) inclusive message
    return {
        action => $response,
        %session_data
    };
}


=head2 handle_error

Called on error from handle_child method

Returns on of the following stati:

=over

=item * ok

A non fatal error (eg timeout of a single module)

=item * spam

Mail recognized as spam

=back

=cut

sub handle_error {
    my ( $self, $err, $child ) = @_;
    
    my $session = $self->session;
    
    # handle error, if any
    given ( $err ) {
        
        # REJECT
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Reject' ) ) {
            $session->add_message( $_->message );
            return 'spam';
        }
        
        # OK
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Accept' ) ) {
            $session->add_message( $_->message );
            return 'ok';
        }
        
        # PREPEND (finish with response)
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Prepend' ) ) {
            $session->add_message( $_->message );
            return 'prepend';
        }
        
        # ERROR
        when( defined $_ && "$_" ne "" ) {
            $self->logger->error( "Error in $child: $_" );
            return 'ongoing';
        }
        # DUNNO
        default {
            $self->logger->debug2( "State after $child: ". $self->session->response );
            return 'ongoing';
        }
    }
    
    return 'ongoing';
}


#
#               RUNTIME
#


=head2 start

Starts all POE servers without calling the POE::Kernel->run

=cut

sub start {
    my ( $self ) = @_;
    
    # setup lockers (shared between all childs)
    $self->set_locker( 'default' );
    $self->set_locker( 'database' );
    $self->set_locker( 'reporting' )
        if $self->config->{ reporting };
}

=head2 run 

Start and run the server via POE::Kernel->run

=cut

sub run {
    my ( $self ) = @_;
    $self->start();
    
    my $server = Mail::Decency::Core::NetServer::Doorman->new( {
        doorman => $self,
    } );
    my $instances = $self->config->{ server }->{ instances } > 1 ? $self->config->{ server }->{ instances } : 2;
    $server->run(
        port              => $self->config->{ server }->{ port },
        host              => $self->config->{ server }->{ host },
        min_servers       => $instances -1,
        max_servers       => $instances +1,
        min_spare_servers => $instances -1,
        max_spare_servers => $instances,
        no_client_stdout  => 1,
    );
}



#
#               SESSION
#


=head2 session_init $attributes_ref

Called at start of every handle cycle. Inits all handle/session-variables

=cut

sub session_init {
    my ( $self, $attrs_ref ) = @_;
    
    # assure we have that:
    $attrs_ref->{ instance } ||= "NOQUEUE-". time(). int( rand() * 999999 );
    
    # create new session
    my $session = Mail::Decency::Core::SessionItem::Doorman->new(
        id                  => $attrs_ref->{ instance },
        cache               => $self->cache,
        from                => $attrs_ref->{ sender } || "",
        to                  => $attrs_ref->{ recipient } || "",
        ip                  => $attrs_ref->{ client_address } || "",
        helo                => $attrs_ref->{ helo_name } || "",
        hostname            => $attrs_ref->{ client_name } || "",
        attrs               => $attrs_ref,
        recipient_delimiter => $self->recipient_delimiter
    );
    
    # add the sign key, if we can   
    $session->sign_key( $self->forward_sign_key_priv )
        if $self->has_forward_sign_key;
    
    # check wheter session already in cache (Doorman might have multiple instances
    my $cached;
    if ( ( $cached = $self->cache->get( "DOORMAN-$attrs_ref->{ instance }" ) ) && ref( $cached ) ) {
        $session->update_from_cache( $cached );
    }
    
    # set session
    $self->session( $session );
    
    # get recipient prefix and domain
    ( $attrs_ref->{ recipient_prefix }, $attrs_ref->{ recipient_domain } )
        = split( /@/, $attrs_ref->{ recipient }, 2 );
    $attrs_ref->{ recipient_address } = $attrs_ref->{ recipient };
    
    # get sender prefix and domain
    ( $attrs_ref->{ sender_prefix }, $attrs_ref->{ sender_domain } )
        = split( /@/, $attrs_ref->{ sender }, 2 );
    $attrs_ref->{ sender_address } = $attrs_ref->{ sender };
    
    return $attrs_ref;
}


=head2 session_cleanup

Clears all info from session cache, returns final response

=cut

sub session_cleanup {
    my ( $self ) = @_;
    
    # get current response
    my $session = $self->session;
    my $response = $session->response;
    
    # set prepended info
    if ( ( $response eq 'DUNNO' || $response eq 'PREPEND' ) && ! $self->disable_prepend ) {
        
        # generate the header ..
        my ( $header, $sign_error )
            = $session->generate_instance_header( $self->forward_scoring );
        $self->logger->error( "Sign error: $sign_error" )
            if $sign_error;
        
        
        # header will look like this:
        #  X-Decency-Instance: <instance>|<sign>|<weight>|<flag,flag,...>|<detail>|<detail>|...
        #   this is tested under postfix with up to 10_000 characters! Postfix splits the
        #   lines at 989 characters, but transports all of them.
        $response = 'PREPEND X-Decency-Instance: '. $header;
    }
    
    elsif ( $response =~ /^(?:[45]\d\d|REJECT)/ ) {
        # determine reject message (could be from multiple modules)
        my $message = $self->no_reject_detail || $session->has_no_message
            ? $self->default_reject_message
            : $session->message_str( ' / ' )
        ;
        $message .= ' ['. $session->identifier. ']'
            unless $self->no_session_identifier;
        
        $response .= " $message";
    }
    
    # update/insert cache
    $self->cache->set( "DOORMAN-". $session->id => $session->for_cache, time()+ 600 );
    
    # remove from session
    $session->cleanup;
    
    # return bool wheter first instance or not
    return $response;
}



#
#               SCORING / STATE CHANGE
#


=head2 add_spam_score $module, $weight, $details, $reject_message

Add weight and filter info to current instance.

Throws _FinalStateException if weighting indicates spam

=over

=item * $module

The module which called the method.

=item * $weight

Positive or negative score.

=item * $details

Details for the MIME header

=item * $reject_message

If this scoring makes the rejection final, this is the rejection message

=back

=cut

sub add_spam_score {
    my ( $self, $module, $weight, %params ) = @_;
    
    my $message = $params{ message } || $params{ m }
        || $params{ message_and_detail } || $params{ md };
    $message = join( "; ", @$message ) if ref( $message ) eq 'ARRAY';
    my $details  = $params{ detail } || $params{ d }
        || $params{ message_and_detail } || $params{ md };
    $details = join( "; ", @$details ) if ref( $details ) eq 'ARRAY';
    
    # get info ref
    my $session = $self->session;
    
    # increment weight
    $session->add_spam_score( $weight );
    
    # add details (X-Decency-Details header)
    my @details = ( "Module: $module", "Score: $weight" );
    push @details, $details if $details;
    $session->add_spam_details( join( "; ", @details ) );
    
    # add response
    $session->add_message( $message );
    
    # being spam -> go to final state (end processing)
    if ( $self->spam_threshold_reached( $session->spam_score ) ) {
        $self->logger->debug0( "Threshold hit after ". $module->name. " with: ". $session->spam_score. " <= ". $self->spam_threshold );
        
        # send reject message
        $self->go_final_state( $module => 'REJECT' );
    }
    
    # no spam, return ..
    return 0;
}



=head2 go_final_state $module, $state, $message

Throws Mail::Decency::Core::Exception exception if state is not DUNNO.

Adds message to list of response messages 


=cut

sub go_final_state {
    my ( $self, $module, $state, $message ) = @_;
    
    $message ||= ''; # $message //= '';
    
    # check staate
    my $final_states = ALLOWED_RESPONSE_STATES;
    unless ( $state =~ $final_states ) {
        Mail::Decency::Core::Exception::ModuleError->throw( {
            message => "Not allowed final state: '$state'"
        } );
    }
    
    # going final state .. (all states but DUNNO
    if ( $state && $state ne 'DUNNO' ) {
        
        # set final state in session
        $self->session->response( $state );
        
        # final OK (accept)
        if ( $state eq 'OK' ) {
            Mail::Decency::Core::Exception::Accept->throw( { message => $message } );
        }
        
        # final PREPEND (OK, but some header to be added)
        elsif ( $state eq 'PREPEND' ) {
            Mail::Decency::Core::Exception::Prepend->throw( { message => $message } );
        }
        
        # assume REJECT
        else {
            Mail::Decency::Core::Exception::Reject->throw( { message => $message } );
        }
    }
    
    # final state DUNNO -> just add response message, do not end!
    elsif( $message ) {
        $self->session->add_message( $message );
    }
}



=head1 SEE ALSO

=over

=item * L<Mail::Decency::Doorman::Association>

=item * L<Mail::Decency::Doorman::CBL>

=item * L<Mail::Decency::Doorman::CWL>

=item * L<Mail::Decency::Doorman::Core>

=item * L<Mail::Decency::Doorman::DNSBL>

=item * L<Mail::Decency::Doorman::Greylist>

=item * L<Mail::Decency::Doorman::GeoWeight>

=item * L<Mail::Decency::Doorman::Honeypot>

=item * L<Mail::Decency::Doorman::SPF>

=item * L<Mail::Decency::Doorman::Throttle>

=item * L<Mail::Decency::Core::Stats>

=item * L<Mail::Decency::Core::SessionItem>

=item * L<Mail::Decency::Core::SessionItem::Doorman>

=item * L<Mail::Decency>

=back


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

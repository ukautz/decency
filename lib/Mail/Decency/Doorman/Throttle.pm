package Mail::Decency::Doorman::Throttle;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
    Mail::Decency::Doorman::Model::Throttle
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );


use Scalar::Util qw/ weaken /;
use POSIX qw/ ceil /;
use Data::Dumper;

=head1 NAME

Mail::Decency::Doorman::Throttle

=head1 DESCRIPTION

Throtle mail sending for dedicated sources (sender ip, sender username, sender address, "account")

=over

=item * client address

The IP of the client connecting to the server.


=item * sender username, sender domain, sender address

The username is the (if any provided) sasl username

=item * recipient domain, recipient address

Caution with this. You don't want your incoming mails to be rejected!

=item * account

An account is a context, binding multiple sender domains / sender addresses . You can associate each row in the database with an column called "account". The counter for throtteling will then be applied to this value instead of sender or such.

Example usecase: There are domain1.tld and domain2.tld. The task is to limit the max amount for sending to 500 Mails per day for both domains together.

=back

=head1 CONFIG

Those are the config params in YAML

    ---
    
    disable: 0
    
    # Whether affect ONLY those having a sasl username set.
    #   Use this if you have one mailserver for incoming AND outgoing
    #   mails. This does not check the validity of the sasl user!
    require_sasl_username: 1
    
    # The default limits, if no exception is in the exception database.
    #   You can use:
    #       * client_address (ip of sending client)
    #       * sender_domain (domain part of sender)
    #       * sender_address (email address of sender)
    #       * sasl_username (the sasl username, if any)
    #       * sender_domain (domain part of sender)
    #       * recipient_domain (domain part of the recipient)
    #       * recipient_address (email address of recipient)
    #       * account (the account.. see above)
    default_limits:
        
        # the following can be read as:
        #   * Account per sender domain
        #   * It is not allowed to send more then:
        #       * 1 Mail per 10 Seconds
        #       * 50 Mails per 10 Minutes
        #       * 1000 Mails per day
        sender_domain:
            -
                maximum: 1
                interval: 10
            -
                maximum: 50
                interval: 600
            -
                maximum: 1000
                interval: 86400
        account:
            -
                maximum: 50
                interval: 600
    
    # which exception database to use (see above)
    #   use only those you really have to. Don't activate all
    #   without actually having data!
    exception_databases:
        - sender_domain
        - sender_address
    
    # The reject messages per interval (above)
    #   Don't forget the rejection code (better use 4xx for
    #   temporary, instead of 5xx for hard)
    reject_messages:
        10:
            message: 'Sorry, not more then one mail in ten seconds'
            code: 450
        600:
            message: 'Sorry, not more then 50 mails in ten minutes'
            code: 450
        86400:
            message: 'Sorry, not more then 1000 mails per day'
            code: 450
    
    # The default error message which will be used if none is set
    #   for the interval.. comes in handy if you use exception 
    #   database with custom intervals
    #   Variables you can use are:
    #       * %maximum% (limit of mails in interval)
    #       * %interval% (interval in seconds)
    #       * %interval_minutes% (interval in minutes, round up)
    #       * %interval_hours% (interval in hours, round up)
    #       * %interval_days% (interval in days, round up)
    default_reject_message:
        message: 'Sorry, not more then %maximum% mails in %interval_minutes% minutes'
        code: 450
    

=cut

our @REGULAR_DATABASES = qw/ client_address sender_domain sasl_username sender_address recipient_domain recipient_address /;
our @ALL_DATABASES = ( @REGULAR_DATABASES, 'account' );
our %ALLOWED_DATABASES = map { ( $_ => 1 ) } @ALL_DATABASES;


=head1 CLASS ATTRIBUTES


=head2 default_reject_message : HashRef

Default reject message and default reject code

    {
        message => 'Sorry, Limit reached (%maximum% mails in %interval% seconds)',
        code    => 450
    }

=cut

has default_reject_message  => ( is => 'rw', isa => 'HashRef', default => sub { {
    message => 'Sorry, Limit reached (%maximum% mails in %interval% seconds)',
    code    => 450
} } );

=head2 reject_messages : HashRef[HashRef]

Reject messages per interval

    {
        10 => {
            message => 'Sorry, Limit reached .. not more then 99 in 10 seconds',
            code    => 450
        },
        86400 => {
            message => 'Sorry, Limit reached .. not more then 101 in 24 hours',
            code    => 450
        }
    }

=cut

has reject_messages => ( is => 'rw', isa => 'HashRef[HashRef]', default => sub { {} } );

=head2 default_limits : HashRef

Limits per attribute ( sender_domain, client_address, recipient_domain, account, .. )

    {
        sender_domain => [
            {
                maximum => 99,
                interval => 10,
            }
        ],
    }

=cut

has default_limits => ( is => 'rw', isa => 'HashRef' );

=head2 default_limit_databases : ArrayRef[HashRef]

Which limit databases .. internal usage

=cut

has default_limit_databases => ( is => 'rw', isa => 'ArrayRef[HashRef]', default => sub { [] } );

=head2 exception_database : HashRef

Exception from default values (eg per account, per sender_domain, whatever)

=cut

has exception_database => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

=head2 used_databases : ArrayRef[Str]

Internal usage..

=cut

has used_databases => ( is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] } );


=head2 use_accounts : Bool

Whether accounts (see description) should be used or not (cost performance)

=cut

has use_accounts => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 counter_increment : CodeRef

Internal usage..

=cut

has counter_increment => ( is => 'rw', isa => 'CodeRef' );

=head2 counter_read : CodeRef

Internal usage..

=cut

has counter_read => ( is => 'rw', isa => 'CodeRef' );

=head2 require_sasl_username : CodeRef

Enable throttle module only if sasl_username is given (this happens if the SMTP connection contains AUTH information.. )

=cut

has require_sasl_username => ( is => 'rw', isa => 'Bool', default => 0 );


=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    my %used_database = ();
    
    # having exception databases ? which to use ?
    my $min_ok = 0;
    if ( $self->config->{ exception_databases } ) {
        die "exception_databases has to be an array\n"
            unless ref( $self->config->{ exception_databases } ) eq 'ARRAY';
        
        # having non empty amount of databases
        if ( scalar @{ $self->config->{ exception_databases } } > 0 ) {
            
            # check database
            foreach my $db( @{ $self->config->{ exception_databases } } ) {
                
                # oops, unknwon database name!
                die "Unknown database '$db' in 'exception_databases' (allowed databases: ". join( ", ", @ALL_DATABASES ). ")\n"
                    unless $ALLOWED_DATABASES{ $db };
                
                # found ok, rememeber
                $min_ok++;
                $used_database{ $db } ++;
                $self->exception_database->{ $db } ++;
            }
        }
    }
    
    # oops, no having any
    if ( $self->config->{ default_limits } ) {
        die "default_limits has to be a hash\n"
            unless ref( $self->config->{ default_limits } ) eq 'HASH';
        
        # parse limit config..
        while( my ( $db, $ref ) = each %{ $self->config->{ default_limits } } ) {
            die "Unknown database '$db' in 'default_limits' (allowed databases: ". join( ", ", @ALL_DATABASES ). ")\n"
                unless $ALLOWED_DATABASES{ $db };
            
            # remember as used
            $used_database{ $db } ++;
            $min_ok ++;
        }
        
        $self->default_limits( $self->config->{ default_limits } );
        
        # add ORDERED list of default limit databaseds
        foreach my $db( @ALL_DATABASES ) {
            push @{ $self->default_limit_databases }, $db
                if $self->default_limits->{ $db };
        }
    }
    
    # min reqs not satisfied
    die "Min requirements for Throttle: 'default_limits' and/or 'exception_databases'\n"
        unless $min_ok;
    
    # build up ORDERED list of actual used databases
    foreach my $db( @ALL_DATABASES ) {
        push @{ $self->used_databases }, $db
            if $used_database{ $db };
    }
    
    # enabled account style ?
    $self->use_accounts( 1 ) if $used_database{ account };
    
    # read reject messages (per interval and default)
    $self->reject_messages( $self->config->{ reject_messages } || {} );
    $self->default_reject_message( $self->config->{ default_reject_message } )
        if $self->config->{ default_reject_message };
    
    # @ future @
    # Hopefully, some kind of LogParser will be re-integrated some day to account for
    #   really sent mails (this can only count sent attempts)
    # @ future @
    $self->counter_read( sub {
        my ( $self, $name, $value, $interval ) = @_;
        my $time = time();
        $time -= $time % $interval;
        return $self->cache->get( 'throttle-'. $name. '-'. $value. '-'. $time ) || 0;
    } );
    $self->counter_increment( sub {
        my ( $self, $name, $value, $interval ) = @_;
        my $time = time();
        $time -= $time % $interval;
        my $amount = $self->counter_read->( $self, $name, $value, $interval );
        return $self->cache->set( 'throttle-'. $name. '-'. $value. '-'. $time, $amount+1 );
    } );
    
    # whether require require_sasl_username
    $self->require_sasl_username( $self->config->{ require_sasl_username } ? 1 : 0 );
    
    return ;
}



=head2 handle

=cut

sub handle {
    my ( $self ) = @_;
    
    # check for sasl username
    return if $self->require_sasl_username && ! $self->sasl;
    
    
    #
    # CACHES
    #
    
    # check all caches
    my %cache_name = ();
    foreach my $db( @{ $self->used_databases } ) {
        next if $db eq 'account';
        $cache_name{ $db } = "Throttle-$db-". $self->attrs->{ $db };
        my $cached = $self->cache->get( $cache_name{ $db } );
        if ( $cached ) {
            $self->logger->debug0( "Cache hit for '$db' = '". $self->attrs->{ $db }. "'" );
            $self->go_final_state( $cached );
        }
    }
    
    # check accont cache
    my $account;
    if ( $self->use_accounts ) {
        
        # and again: for any database (should be faster that way then one loop, cause we
        #   reduce database reads this way!
        foreach my $db( @{ $self->used_databases } ) {
            next if $db eq 'account';
            
            # try find account
            $account = $self->get_account( $db => $self->attrs->{ $db } );
            next unless $account;
            
            # found account
            $cache_name{ account } = "Throttle-account-$account";
            
            # try cache
            if ( defined( my $cached = $self->cache->get( $cache_name{ account } ) ) ) {
                $self->logger->debug3( "Cache hit for account '$account' of '$db' = '". $self->attrs->{ $db }. "'" );
                $self->go_final_state( $cached );
            }
            
            # anyway, we know who the account is for now
            last;
        }
    }
    
    
    #
    # DATABASE
    #
    my $attrs_ref = $self->attrs;
    $attrs_ref->{ account } = $account ||= "**UNDEFINED ACCOUNT**";
    
    # try database now
    CHECK_DATABASE:
    foreach my $db( @{ $self->used_databases } ) {
        next CHECK_DATABASE
            if $db eq 'account' && ! $account;
        
        # performance: ignore this one
        my $ignore_cache = sprintf( 'Ignore-Throttle-%s-%s',
            $attrs_ref->{ $db }, $attrs_ref->{ $db } );
        if ( $self->cache->get( $ignore_cache ) ) {
            next CHECK_DATABASE;
        }
        
        my @limits;
        my $exception = 0;
        
        # we could find in exception database..
        if ( $self->exception_database->{ $db } ) {
            @limits = $self->database->search( throttle => $db, {
                $db => $attrs_ref->{ $db }
            } );
            $exception ++ if @limits;
        }
        
        # no exceptions? -> try fallback to defaults
        if ( ! @limits && defined $self->default_limits->{ $db } ) {
            @limits = @{ $self->default_limits->{ $db } };
        }
        
        # no limits at all -> bye
        unless ( @limits ) {
            $self->cache->set( $ignore_cache, 'IGNORE', 300 );
            next CHECK_DATABASE;
        }
        
        $self->logger->debug3( "Using ". ( $exception ? "Exception" : "Default" ). " limits for $attrs_ref->{ $db } ($db)" )
            if @limits;
        
        # go through all limits -> first rejection counts
        foreach my $limit_ref( @limits ) {
            # now ..
            my $now = time();
            
            # get counter, which is the max counter for all db items
            my $count = $self->counter_read->(
                $self, $db, $attrs_ref->{ $db }, $limit_ref->{ interval } );
            
            $self->logger->debug3( " Limit $count / $limit_ref->{ maximum } in $limit_ref->{ interval }" );
            
            # limit reached
            if ( $limit_ref->{ maximum } >= 0 && $count >= $limit_ref->{ maximum } ) {
                
                # get reject message (either special for this limit or default)
                my $reject_message_ref = 
                    $self->reject_messages->{ $limit_ref->{ interval } }
                    || $self->default_reject_message;
                
                my $reject_message = $reject_message_ref->{ message };
                
                # parse output message
                $reject_message =~ s/%interval%/$limit_ref->{ interval }/g;
                
                my $interval_minutes = ceil( $limit_ref->{ interval } / 60 );
                $reject_message =~ s/%interval_minutes%/$interval_minutes/g;
                
                my $interval_hours = ceil( $limit_ref->{ interval } / 3600 );
                $reject_message =~ s/%interval_hours%/$interval_hours/g;
                
                my $interval_days = ceil( $limit_ref->{ interval } / 86400 );
                $reject_message =~ s/%interval_days%/$interval_days/g;
                
                $reject_message =~ s/%maximum%/$limit_ref->{ maximum }/g;
                
                # write state to cache
                my $timeout = $limit_ref->{ interval } - ( $now % $limit_ref->{ interval } );
                $self->cache->set( $cache_name{ $db }, $reject_message, $timeout );
                
                # log event
                $self->logger->debug0( " !! Limit reached for '$db' = '$attrs_ref->{ $db }' ($limit_ref->{ interval })!!" );
                
                # get reject code
                my $reject_code = $reject_message_ref->{ code } || 450;
                
                # set final state (throws exception)
                $self->go_final_state( $reject_code => $reject_message );
            }
            else {
                $self->logger->debug3( "  No limit issue" );
            }
            
            
            # increase counter now
            $self->counter_increment->(
                $self,  $db, $attrs_ref->{ $db }, $limit_ref->{ interval } );
        }
    }
    
}



=head2 get_account $db, $value

returns account by attribute lookup

    my $account = $self->get_account( sender_domain => 'sender.tld' );

=cut

sub get_account {
    my ( $self, $db, $value ) = @_;
    
    # from cache ??
    my $cache_name = "Throttle-account-$db-$value";
    if ( defined( my $cached = $self->cache->get( $cache_name ) ) ) {
        return $cached;
    }
    
    # from database ..
    my $ref = $self->database->get( throttle => $db => { $db => $value } );
    if ( $ref && $ref->{ account } ) {
        
        # save to cache
        $self->cache->set( $cache_name => $ref->{ account } );
        return $ref->{ account };
    }
    
    # nothing found
    return;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut




1;

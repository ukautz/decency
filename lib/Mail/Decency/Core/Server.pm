package Mail::Decency::Core::Server;


use Mouse;
with qw/
    Mail::Decency::Core::Meta
    Mail::Decency::Core::Locker
    Mail::Decency::Core::Meta::Database
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use Scalar::Util qw/ weaken blessed /;
use Time::HiRes qw/ tv_interval gettimeofday /;

use Mail::Decency::Helper::Cache;
use Mail::Decency::Helper::Database;
use Mail::Decency::Helper::Logger;

use YAML;


=head1 NAME

Mail::Decency::Core::Server

=head1 DESCRIPTION

Base module for all decency servers (Doorman, Detective).

=head1 CLASS ATTRIBUTES

=head2 inited : Bool

Wheter the server is inited or not

=cut

has inited => ( is => 'ro', isa => 'Bool' );

=head2 _reloading : Bool

=cut

has _reloading => ( is => 'rw', isa => 'Bool', default => 0 );


=head2 childs : ArrayRef[Mail::Decency::Core::Child]

List of all (enabled) modules for this server.. Will be required when called handle

=cut

has childs => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] }
);

=head2 is_child : Bool

=cut

has is_child => (
    is        => 'ro',
    isa       => 'Bool',
    traits    => [qw/ MouseX::NativeTraits::Bool /],
    handles   => {
        this_is_a_child => 'set'
    },
    default   => 0
);

=head2 database : Mail::Decency::Helper::Database

Database handle

=cut

has database => ( is => 'ro', isa => 'Mail::Decency::Helper::Database' );

=head2 recipient_delimiter : Str

If set, everything in the prefix part of the mail after this character will be ignore.
Eg, if "recipient_delimiter" is set to "+" and the a recipient mail looks like
"user+something@domain.tld", decency will pretend the mail is "user@domain.tld" which
then again will allow for matches of "user@domain.tld" in the module databases.

=cut

has recipient_delimiter => ( is => 'rw', isa => 'Str', default => '' );

=head2 schema_definition

Init schema definition for all databases

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub { {} } );

=head2 _hooks

Hooks for server hooks

=cut

has _hooks => ( is => 'ro', isa => 'HashRef', default => sub { {} } );


=head1 METHODS

=head2 init

Init class for the server

=cut

sub init {
    die "Init method has to be overwritten by server methosd\n";
}


=head2 init_postfix_server

Setup POE::Component::Server::Postfix

=cut

sub init_postfix_server {
    my ( $self ) = @_;
    
    # check server config
    die "server config missing!\n"
        unless defined $self->config->{ server } && ref( $self->config->{ server } ) eq 'HASH';
    die "set either host and port OR socket for server\n"
        if (
            ! defined $self->config->{ server }->{ host }
            && ! defined $self->config->{ server }->{ port }
            && ! defined $self->config->{ server }->{ socket }
        ) || (
            defined $self->config->{ server }->{ host }
            && defined $self->config->{ server }->{ socket }
        );
    
    return 1;
}


=head2 init_logger

Setup logger facility

=cut

sub init_logger {
    my ( $self ) = @_;
    
    # setup logger
    ( my $prefix = ref( $self ) ) =~ s/^.*:://;
    weaken( my $self_weak = $self );
    my $logger = Mail::Decency::Helper::Logger->new(
        %{ $self->config->{ logging } },
        prefix => $prefix,
        server => $self_weak
    );
    $self->{ logger } = $logger;
    # $self->{ logger } = sub {
    #     $logger->log( @_ );
    # };
    
    return 1;
}


=head2 init_cache

Setup cache facility ( $self->cache )

=cut

sub init_cache {
    my ( $self ) = @_;
    
    # setup cache
    die "cache config missing!\n"
        unless defined $self->config->{ cache };
    $self->{ cache } = blessed( $self->config->{ cache } )
        ? $self->config->{ cache }
        : Mail::Decency::Helper::Cache->new( %{ $self->config->{ cache } } )
    ;
    
    return 1;
}


=head2 init_database

Initi's database

=cut

sub init_database {
    my ( $self ) = @_;
    
    # setup cache
    die "database config missing!\n"
        unless defined $self->config->{ database };
    
    if ( blessed( $self->config->{ database } ) ) {
        $self->{ database } =  $self->config->{ database };
    }
    else {
        my $type = $self->config->{ database }->{ type }
            or die "Missing type for database (main)!\n";
        weaken( my $self_weak = $self );
        eval {
            $self->{ database } = Mail::Decency::Helper::Database
                ->create( $type => $self->config->{ database }, $self_weak );
        };
        die "Cannot create main database: $@\n" if $@;
    }
    
    # copy logger
    $self->database->logger( $self->logger );
    
    # register schema definition
    $self->database->register( $self->schema_definition )
        if $self->can( 'schema_definition' );
    
    if ( $ENV{ SETUP_DATABASE } ) {
        $self->database->setup( $self->schema_definition,
            { execute => 1, test => 1, register => 1 } );
    }
    else {
        $self->database->register( $self->schema_definition );
    }
    
    $self->database->logger( $self->logger->clone( "$self/db" ) );
}


=head2 init_server_shared

Init other shared values besides cache, database, ..

=cut

sub init_server_shared {
    my ( $self ) = @_;
    
    # check modules..
    $self->config->{ modules } = []
        unless defined $self->config->{ modules }
        && ref( $self->config->{ modules } ) eq 'ARRAY'
        && scalar @{ $self->config->{ modules } } > 0;
    
    # use weighting ?
    if ( defined $self->config->{ spam_threshold } ) {
        $self->spam_threshold( $self->config->{ spam_threshold } );
    }
    
    # delimiter
    if ( my $delimiter = $self->config->{ recipient_delimiter } ) {
        $self->recipient_delimiter( $delimiter );
    }
}


=head2 run 

Run the server

=cut

sub run {
    die "Run method has to be overwritten my server\n";
}


=head2 gen_child

=cut

sub gen_child {
    my ( $self, $base, $name, $config_ref, $init_args_ref ) = @_;
    
    # if not hashref as config .. check wheter file
    if ( ! ref( $config_ref ) ) {
        
        # having config dir ?
        if ( ! $self->has_config_dir && defined $self->config->{ config_dir } ) {
            if ( -d $self->config->{ config_dir } ) {
                $self->config_dir( $self->config->{ config_dir } );
            }
            else {
                die "Provided config_dir '". $self->config->{ config_dir }. "' is not a directory or not readable\n";
            }
        }
        
        # having dir-name ?
        if ( ! -f $config_ref && $self->has_config_dir && -f $self->config_dir . "/$config_ref" ) {
            $config_ref = $self->config_dir . "/$config_ref";
        }
        
        # having file ..
        if ( -f $config_ref ) {
            eval {
                $config_ref = YAML::LoadFile( $config_ref );
            };
            if ( $@ ) {
                die "Error loading config file '$config_ref' for $name: $@\n";
            }
        }
        else {
            die "Sorry, cannot find config file '$config_ref' for $name. (config_dir: ". ( $self->has_config_dir ? $self->config_dir : "not set" ). ")\n"; 
        }
    }
    
    # being disabled ?
    if ( $config_ref->{ disable } ) {
        $self->logger->debug3( "$name is disabled" );
        return;
    }
    
    # weak reference to self
    weaken( my $self_weak = $self );
    
    # get no-cache instance (for modules where caching is disabled)
    my $no_cache = Mail::Decency::Helper::Cache->new( class => 'none' );
    
    # havin extra databas for this fellow ?
    my $database;
    if ( defined $config_ref->{ database } ) {
        my $type = $config_ref->{ database }->{ type }
            or die "Missing required 'type' for database ($name)!\n";
        weaken( my $self_weak = $self );
        eval {
            $database = Mail::Decency::Helper::Database
                ->create( $type => $config_ref->{ database }, $self_weak );
        };
        $database->server( $self_weak );
        die "Cannot create database for $name: $@\n" if $@;
    }
    else {
        weaken( $database = $self->database );
    }
    
    # determine module base
    my @module_classes = ( "${base}::${name}", "${base}::${name}" );
    $module_classes[0] =~ s/::Decency::/::DecencyX::/;
    my $module;
    foreach my $module_class( @module_classes ) {
        eval "use $module_class; 1;" && do {
            $module = $module_class;
            last;
        };
    }
    die "Missing Doorman module '$name' (tried: ". join( ', ', @module_classes ). ")\n"
        unless $module;
    
    # create instance of sub module
    my $obj;
    eval {
        my $logger = $self->logger->clone( lc( $self->logger->prefix. "/$name" ) );
        
        # delegate logger if new database
        $database->logger( $logger->clone( "$self/db" ) )
            if ( defined $config_ref->{ database } );
        
        # create the object itself
        $obj = $module->new(
            name     => $name,
            config   => $config_ref,
            cache    => $config_ref->{ no_cache } ? $no_cache : $self->cache,
            database => $database,
            server   => $self,
            logger   => $logger,
            %$init_args_ref
        );
        
        
        # in any case: register database
        if ( $obj->can( 'schema_definition' ) ) {
            if ( $ENV{ SETUP_DATABASE } ) {
                $obj->database->setup( $obj->schema_definition,
                    { execute => 1, test => 1, register => 1 } );
            }
            else {
                $obj->database->register( $obj->schema_definition );
            }
        }
        
        if ( $obj->can( 'check_database' ) && ! $ENV{ DECENCY_NO_CHECK_DATABASE } ) {
            ( my $db_class = ref( $self->database ) ) =~ s/^.+:://;
            $obj->check_database( $obj->schema_definition )
                or die "Please create the database yourself (class: $db_class)\n";
        }
        
    };
    
    die "Error creating $name: $@\n" if $@;
    
    
    return $obj;
}

=head2 load_modules

Loads all modules via the "gen_child" method

=cut

sub load_modules {
    my ( $self ) = @_;
    $self->childs( [] );
    
    foreach my $module_ref( @{ $self->config->{ modules } } ) {
        my ( $name, $config_ref ) = %$module_ref;
        $self->logger->debug1( "Load module '$name' for '". ref( $self ). "'" );
        my $module = $self->gen_child( ref( $self ) => $name => $config_ref );
        
        # add to meta list of childs
        push @{ $self->childs }, $module;
        
        $module_ref->{ $name } = $module->config if $module;
    }
}


=head2 reload

Reload configuration

=cut

sub reload {
    my ( $self ) = @_;
    $self->config( merged_config( $ENV{ DECENCY_CMD_OPTIONS } || {} ) );
    $self->init_reloadable();
}


=head2 maintenance 

Call maintenance, cleanup databases.

=cut

sub maintenance {
    my ( $self ) = @_;
    
    $self->logger->debug1( "Running in maintenance mode" );
    
    foreach my $child( @{ $self->childs } ) {
        $child->maintenance() if $child->can( 'maintenance' );
    }
    
    $self->logger->debug1( "Maintenance performed" );
    
    exit 0;
}



=head2 handle_child

=cut

sub handle_child {
    my ( $self, $child, $args_ref ) = @_;
    
    return 0
        if $self->has_exclusions && $self->do_exclude( $child );
    
    # determine weight before, so we can increment stats
    my $score_before   = $self->session->spam_score;
    my $start_time_ref = [ gettimeofday() ];
    
    eval {
        
        # set alarm if timeout enabed
        my $alarm = \( local $SIG{ ALRM } );
        if ( $child->timeout ) {
            $$alarm = sub {
                Mail::Decency::Core::Exception::Timeout->throw( { message => "Timeout" } );
            };
            alarm( $child->timeout + 1 );
        }
        
        # check size.. if to big for filter -> don't handle
        if (
            $child->can( 'Mail::Decency::Detective::Core' )
            && $child->can( 'max_size' )
            && $child->max_size
            && $self->session->file_size > $child->max_size
        ) {
            Mail::Decency::Core::Exception::FileToBig->throw( { message => "File to big" } );
        }
        
        # run the filter on the current file
        else {
            $child->exec_handle( @$args_ref );
        }
    };
    my $err = $@;
    
    # reset alarm
    alarm( 0 ) if $child->timeout;
    
    # assure clearup is executed
    eval {
        $child->clearup();
    };
    $self->logger->error( "Error in clearup of $child: $@" )
        if $@;
    
    # having error -> check if errro and error implies finish
    my $state = $err || ref( $err )
        ? $self->handle_error( $err, $child )
        : 'ongoing'
    ;
    $self->logger->debug0( "Mail from ". $self->session->from. " -> ". $self->session->to. ": (module/state/err) = ('$child'/'$state'/'$err')" );

    
    # stats ?
    if ( $self->enable_module_stats ) {
        
        # diff ..
        my $score_diff = $self->session->spam_score - $score_before;
        
        # get the status for saving
        my $write_status = $self->session->can( 'response' )
            ? $self->session->response
            : $state
        ;
        
        # run finish hooks
        # ( $state ) = $self->run_hooks( 'post_module', [ {
        #     state   => $write_status,
        #     child   => $child,
        #     score   => $score_diff,
        #     runtime => tv_interval( $start_time_ref, [ gettimeofday() ] )
        # } ] );
        
        # update ..
        $self->update_module_stats( $child, $write_status, $score_diff,
            tv_interval( $start_time_ref, [ gettimeofday() ] ) );
    }
    
    return ( 1, $state, $err );
}


=head2 handle_error

=cut

sub handle_error {
    die "handle_error has to be overwritten by class";
}

=head2 run_hooks

=cut

sub run_hooks {
    my ( $self, $name, $attrs_ref ) = @_;
    $attrs_ref ||= [];
    
    # run child hooks
    my $hook_name = "hook_$name";
    foreach my $child( @{ $self->childs } ) {
        next 
            if ! $child->can( $hook_name )
            || ( $self->has_exclusions && $self->do_exclude( $child ) );
        
        eval {
            my @res = $child->$hook_name( @$attrs_ref );
            $attrs_ref = \@res if @res;
        };
        $self->logger->error( "Error in hook '$name' for '$child': $@" ) if $@;
    }
    
    # run server hooks
    if ( defined( my $hooks_queue_ref = $self->_hooks->{ $name } ) ) {
        foreach my $ref( @$hooks_queue_ref ) {
            my ( $meth, $meth_attrs_ref ) = @_;
            eval {
                my @res = $meth->( $self, $meth_attrs_ref, @$attrs_ref );
                $attrs_ref = \@res if @res;
            };
            $self->logger->error( "Error in server hook '$name': $@" ) if $@;
        }
    }
    
    return @$attrs_ref;
}

=head2 register_hook

Register hook in hook queue (for server extensions, modules should use the hook methods).

=cut

sub register_hook {
    my ( $self, $name, $method, $attrs_ref ) = @_;
    push @{ $self->_hooks->{ $name } ||= [] }, [ $method, $attrs_ref ];
}


=head2 spam_threshold_reached

Checks wheter spam threashold is reached or not

=cut

sub spam_threshold_reached {
    my ( $self, $spam_score ) = @_;
    
    if ( $self->enable_custom_scoring ) {
        my $reached = $self->custom_threshold_reached( $spam_score );
        if ( $reached != -1 ) {
            return $reached;
        }
    }
    return $spam_score <= $self->spam_threshold;
}




=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

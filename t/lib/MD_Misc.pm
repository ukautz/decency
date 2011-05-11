package MD_Misc;


use strict;

use base qw/ Exporter /;
use FindBin qw/ $Bin /;
use MD_DB;
use Test::More;
use feature qw/ switch /;
use Scalar::Util qw/ blessed /;
use File::Path qw/ rmtree /;
use Carp qw/confess /;

BEGIN {
    if ( $Bin =~ /\/tests$/ ) {
        $Bin = "$Bin/../core";
    }
    eval 'use IPC::SysV qw/ IPC_PRIVATE IPC_CREAT S_IRWXU /; 1;'
        or BAIL_OUT "Cannot load IPC::SysV which is required for testing:";
    unless ( -d "$Bin/data" ) {
        mkdir "$Bin/data";
        BAIL_OUT "Cannot create temp '$Bin/data' directory"
            unless -d "$Bin/data";
    }
}

$ENV{ NO_DB_DISCONNECT } = 1;

our @EXPORT = qw/
    ok_for_ok ok_for_dunno ok_for_prepend ok_for_reject ok_mime_header
    init_server init_module init_database
    session_init cleanup_server get_semaphore
    empty_logger
/;

our %INFO = (
    Detective => {
        config_file => 'detective',
        create      => {
            spool_dir => "$Bin/data/spool-dir",
        }
    },
    Doorman => {
        config_file => 'doorman',
        create      => {}
    }
);

our %DB_INITED = ();


sub init_server {
    my ( $server_class, $add_config_ref, $args_ref ) = @_;
    $add_config_ref ||= {};
    $args_ref ||= {};
    
    foreach my $mandatory( qw/ YAML Mouse Cache::Memory DBD::SQLite DBI DBIx::Connector SQL::Abstract::Limit / ) {
        unless ( eval "use $mandatory; 1;" ) {

            BAIL_OUT "Cannot load $mandatory which is required for testing: $@";
        }
    }
    
    my ( $semaphore, $sem_error ) = get_semaphore();
    if ( $sem_error ) {
        die $sem_error;
    }
    elsif ( ! $semaphore){
        die "Failed to create Semaphore!";
    }
    
    my $class = "Mail::Decency::$server_class";
    eval "use $class; 1;";
    if ( $@ ) {
        BAIL_OUT "Cannot load server $class: $@";
    }
    
    my $config_ref = YAML::LoadFile( "$Bin/conf/$INFO{ $server_class }->{ config_file }.yml" );
    $config_ref->{ $_ } = $add_config_ref->{ $_ }
        for keys %$add_config_ref;
    
    # bind database
    if ( $ENV{ USE_MONGODB } && $ENV{ USE_MONGODB } == 1 ) {
        $config_ref->{ database } = {
            type     => "MongoDB",
            database => $ENV{ MONGODB_DATABASE } || "test_decency",
            server   => $ENV{ MONGODB_HOST } || "127.0.0.1",
            port     => $ENV{ MONGODB_PORT } || 27017,
        };
    }
    elsif ( $ENV{ USE_LDAP } && $ENV{ LDAP_USER } && $ENV{ LDAP_PASSWORD } && $ENV{ LDAP_BASE } ) {
        $config_ref->{ database } = {
            type     => "LDAP",
            user     => $ENV{ LDAP_USER },
            password => $ENV{ LDAP_PASSWORD },
            base     => $ENV{ LDAP_BASE },
            host     => $ENV{ LDAP_HOST } || 'localhost:389',
        };
    }
    else {
        $config_ref->{ database } = {
            type   => "DBD",
            args   => [ "dbi:SQLite:dbname=". MD_DB::sqlite_file( $args_ref->{ no_db_setup } ) ],
        };
    }
    
    
    # bind cache
    $config_ref->{ cache } = {
        class => "Memory",
    };
    $config_ref->{ config_dir } = "$Bin/conf";
    $config_ref->{ $_ } = $INFO{ $server_class }->{ create }->{ $_ }
        for keys %{ $INFO{ $server_class }->{ create } ||= {} };
    
    # unless ( $class->does( '_RoleCleanup' ) ) {
    #     Mouse::Util::apply_all_roles( $class, qw/ _RoleCleanup / );
    # }
    $class->meta->add_before_method_modifier( DESTROY => sub {
        cleanup_server( shift );
    } );
    
    my $server;
    eval {
        $server = $class->new( config => $config_ref, config_dir => "$Bin/conf" );
        $server->setup();
    };
    BAIL_OUT( "Failed to create server: $@" ) if $@;
    
    return $server;
}

sub init_module {
    my ( $server, $module_name, $extend_ref, $create_ref ) = @_;
    $extend_ref ||= {};
    $create_ref ||= {};
    
    if ( $module_name =~ /^Dummy(Doorman|Detective)(.+?)$/ ) {
        my ( $n1, $n2 ) = ( $1, $2 );
        my $module_class = "DummyModule::${n1}${n2}";
        eval "use $module_class; 1;"
            or die "Cannot load dummy module $module_class: $@\n";
        my $module;
        eval {
            $module = $module_class->new(
                server   => $server,
                name     => $module_name,
                config   => $extend_ref,
                database => $server->database,
                cache    => $server->cache,
                logger   => empty_logger(),
                %$create_ref
            );
        };
        ok( !$@, "Dummy module $module_name loaded" )
            or fail( "Failed to load $module_name: $@" );
        return $module;
    }
    
    ( my $server_class_name = ref( $server ) ) =~ s/.*:://;
    
    ( my $config_file = $module_name ) =~ s/([A-Z])([A-Z]+)/$1. lc($2)/eg;
    $config_file =~ s/^([A-Z])/lc($1)/e;
    $config_file =~ s/([A-Z])/"-". lc($1)/eg;
    
    my $config_ref = YAML::LoadFile( $server->config_dir . "/". $INFO{ $server_class_name }->{ config_file }. "/$config_file.yml" );
    $config_ref->{ $_ } = $extend_ref->{ $_ }
        for keys %$extend_ref;
    my $module_class = ref( $server ). "::". $module_name;
    eval "use $module_class; 1;"
        or return "Could not load '$module_class': $@";
    my $module = $module_class->new(
        server   => $server,
        name     => "Test",
        config   => $config_ref,
        database => $server->database,
        cache    => $server->cache,
        logger   => empty_logger(),
        %$create_ref
    );
    $module_class->meta->add_before_method_modifier( DESTROY => sub {
        cleanup_database( shift );
    } );
    ok( !$@ && $module, "$module_name module loaded" )
        or die( "Problem loading module $module_name: $@" );
    
    # setup test datbase
    ( my $db_class = $module_class ) =~ s/::([^:]+?)$/::Model::$1/;
    if ( eval "use $db_class; 1" ) {
         init_database( $module );
         ok( !$@, "Setup database for $module_name" )
             or die( "Problem setup database for $module_name: $@" );
    }
    
    return $module;
}


sub init_database {
    my ( $module ) = @_;
    return unless $module->can( 'schema_definition' );
    return if $DB_INITED{ ref( $module ) }++;
    
    my $definition_ref = $module->schema_definition;
    $module->database->register( $definition_ref );
    while( my ( $schema, $tables_ref ) = each %$definition_ref ) {
        while ( my ( $table, $columns_ref ) = each %$tables_ref ) {
            unless ( $module->database->ping( $schema => $table => $columns_ref ) ) {
                $module->database->setup( $schema => $table => $columns_ref, { execute => 1, test => 1, register => 1 } );
                die "Database not created\n"
                    unless $module->database->ping( $schema => $table => $columns_ref );
            }
        }
    }
}

sub empty_logger {
    eval 'use Mail::Decency::Helper::Logger;';
    return Mail::Decency::Helper::Logger->new(
        syslog    => 0,
        console   => $ENV{ DEBUG_LOG } || 0,
    );
}

sub get_semaphore {
    eval 'use Mail::Decency::Helper::Locker; 1;'
        or die "Could not load 'Mail::Decency::Helper::Locker': $@";
    my $sem = eval {
        Mail::Decency::Helper::Locker->new( 'database' );
    };
    return ( $sem, $sem ? undef : "Cannot create Mail::Decency::Helper::Locker: $@" );
}

sub session_init {
    my ( $server, @args ) = @_;
    
    if ( ref( $server ) =~ /::Doorman$/ ) {
        my ( $attrs_ref ) = @args;
        $attrs_ref ||= {};
        
        my %default_attr = (
            recipient      => $attrs_ref->{ recipient_address } || 'recipient@default.tld',
            sender         => $attrs_ref->{ sender_address } || 'sender@default.tld',
            client_address => '255.255.255.254',
        );
        my %attrs = ( %default_attr, %$attrs_ref );
        $server->session_init( \%attrs );
    }
    
    else {
        my ( $alternate_file ) = @args;
        
        # there is the orig file
        my $testmail = $alternate_file || "$Bin/sample/eml/testmail.eml";
        open my $fh, '<', $testmail
            or die "Cannot open '$testmail' for read: $!";
        
        # new temp file
        srand;
        my $temp_file = $server->spool_dir. "/temp/mail-". time(). "-". int( rand() * 10000 );
        open my $th, '>', $temp_file
            or die "Canot open temp file '$temp_file' for write: $!";
        
        # copy
        print $th $_ while( <$fh> );
        
        # lose
        close $th;
        close $fh;
        
        $server->session_init( $temp_file, -s $temp_file );
    }
}


sub get_cache_module {
    foreach my $m( qw/ File Memory Memcached FastMmap / ) {
        eval "use Cache::$m; 1"
            and return $m;
    }
    die "Could not load any Cache module.. install Cache::File or Cache::Memory or Cache::Memcached or Cache::FastMmap\n";
}

sub cleanup_server {
    my ( $server ) = @_;
    rmtree( "$Bin/data/cache" );
    
    cleanup_database( $server );
    
    if ( $server->isa( 'Mail::Decency::Detective' ) ) {
        rmtree( $server->spool_dir );
    }
}


sub cleanup_database {
    my ( $obj ) = @_;
    my $db = eval { $obj->database->db };
    return unless $db;
    unless( $ENV{ NO_DB_CLEANUP } ) {
        if ( $ENV{ USE_MONGODB } ) {
            $db->drop;
        }
        
        elsif ( $ENV{ USE_LDAP } && $ENV{ LDAP_BASE } ) {
            eval {
                my $res = $db->search(
                    base   => $ENV{ LDAP_BASE },
                    scope  => 'sub',
                    filter => 'objectClass=*'
                );
                my @remove;
                while( my $item = $res->pop_entry ) {
                    push @remove, $item;
                }
                pop @remove;
                
                foreach my $item( sort { length( $b->dn ) <=> length( $a->dn ) } @remove ) {
                    $db->delete( $item->dn );
                }
            };
        }
        else {
            my $sqlite = MD_DB::sqlite_file();
            unlink( $sqlite ) if -f $sqlite;
        }
    }
}





sub ok_for_reject {
    my ( $server, $err, $msg ) = @_;
    my $ok = 0;
    given( $err ) {
        when( blessed($_) && $_->isa( 'Mail::Decency::Core::Exception::Reject' ) && $server->session->response =~ /^(REJECT|[45]\d\d)/ ) {
            $ok++;
        }
        default {
            diag( "Wrong state: ". $server->session->response. ", expected REJECT or [45]\\d\\d" )
                if $server->session->response !~ /^(REJECT|[45]\d\d)/;
            diag( "Wrong Exception: ". ref( $_ ) )
                if blessed($_) && ! $_->isa( 'Mail::Decency::Core::Exception::Reject' );
            diag( "Unexpected error $_" )
                if ! blessed($_) && $_;
        }
    }
    ok( $ok, $msg );
}


sub ok_for_ok {
    my ( $server, $err, $msg ) = @_;
    my $ok = 0;
    given( $err ) {
        when( blessed($_)
            && $_->isa( 'Mail::Decency::Core::Exception::Accept' )
            && $server->session->response =~ /^OK/
        ) {
            $ok++;
        }
        default {
            diag( "Wrong state: ". $server->session->response. ", expected OK" )
                if $server->session->response !~ /^OK/;
            diag( "Wrong Exception: ". ref( $_ ) )
                if blessed($_) && ! $_->isa( 'Mail::Decency::Core::Exception::OK' );
            diag( "Unexpected error $_" )
                if ! blessed($_) && $_;
        }
    }
    ok( $ok, $msg );
}


sub ok_for_prepend {
    my ( $server, $err, $msg ) = @_;
    my $ok = 0;
    given( $err ) {
        when( blessed($_) && $_->isa( 'Mail::Decency::Core::Exception::Prepend' ) && $server->session->response =~ /^PREPEND/ ) {
            $ok++;
        }
        default {
            diag( "Wrong state: ". $server->session->response. ", expected PREPEND" )
                if $server->session->response !~ /^PREPEND/;
            diag( "Wrong Exception: ". ref( $_ ) )
            if blessed($_) && ! $_->isa( 'Mail::Decency::Core::Exception::Prepend' );
            diag( "Unexpected error $_" )
                if ! blessed($_) && $_;
        }
    }
    ok( $ok, $msg );
}


sub ok_for_dunno {
    my ( $server, $err, $msg ) = @_;
    my $ok = 0;
    given( $err ) {
        when( ! $_ && $server->session->response =~ /^DUNNO/ ) {
            $ok++;
        }
        default {
            diag( "Wrong state: ". $server->session->response. ", expected DUNNO" )
                if $server->session->response !~ /^DUNNO/;
            diag( "Wrong Exception: ". ref( $_ ) )
                if blessed($_);
            diag( "Unexpected error: $_" )
                if ! blessed($_) && $_;
        }
    }
    ok( $ok, $msg );
}


sub ok_mime_header {
    my ( $module, $header, $sub_check, $message ) = @_;
    
    # testing output dir
    my $mime_dir = $module->server->spool_dir. '/temp/mime-temp';
    mkdir( $mime_dir )
        or die "Cannot make temp mime dir '$mime_dir'\n"
        unless -d $mime_dir;
    
    # create new parser
    my $parser = MIME::Parser->new();
    $parser->output_under( $mime_dir );
    
    # reade mime file
    open my $fh, '<', $module->file
        or die "Cannot open mime file '". $module->file. "' for read: $!\n";
    my $entity = $parser->parse( $fh );
    close $fh;
    
    my $res = 0;
    if ( $entity && scalar ( my @values = $entity->head->get( $header ) ) > 0 ) {
        eval {
            $res = $sub_check->( \@values );
        };
        diag( "Error in check method for mime: $@" ) if $@;
    }
    else {
        $res = $sub_check->( [] );
    }
    
    # cleanup
    $parser->filer->purge;
    
    ok( $res, $message );
}




1;

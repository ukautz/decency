#!/usr/bin/perl


use strict;
use warnings;
use FindBin qw/ $Bin /;

BEGIN {
    
    # check all available dirs
    foreach my $dir( (
        '/opt/decency/lib',
        '/opt/decency/locallib',
        '/opt/decency/locallib/lib/perl5',
        "$Bin/../lib"
    ) ) {
        -d $dir && eval 'use lib "'. $dir. '"';
    }
    
    # try load local lib also
    eval 'use local::lib';
}

use version 0.74; our $VERSION = qv( "v0.2.0" );

use YAML;
use Getopt::Long;
use File::Basename qw/ dirname /;
use Mail::Decency::Helper::Shell qw/
    switch_user_group
    pid_is_running
    get_child_pids
/;
use Mail::Decency::Helper::Config qw/
    merged_config
/;
use POSIX 'setsid';

# for start / stop, set buffer to 1
$| = 1;


# get commandline args
my %opt;
GetOptions(
    "class|a=s"            => \( $opt{ class } = "" ),
    "config|c=s"           => \( $opt{ config } = '/etc/decency/%s.yml' ),
    "log-level|l=i"        => \( $opt{ log_level } = 1 ),
    "pid-file|p=s"         => \( $opt{ pid } = "" ),
    "port=i"               => \( $opt{ port } ),
    "host=s"               => \( $opt{ host } ),
    "help|h"               => \( $opt{ help } = 0 ),
    "check|x"              => \( $opt{ check } = 0 ),
    "maintenance"          => \( $opt{ maintenance } = 0 ),
    "print-stats"          => \( $opt{ print_stats } = 0 ),
    "print-sql"            => \( $opt{ print_sql } = 0 ),
    "check-db-structure"   => \( $opt{ check_db_structure } = 0 ),
    "upgrade-db-structure" => \( $opt{ upgrade_db_structure } = 0 ),
    "export=s"             => \( $opt{ export } = "" ),
    "import=s"             => \( $opt{ import } = "" ),
    "import-replace"       => \( $opt{ import_replace } = "" ),
    "user|u=s"             => \( $opt{ user } = "" ),
    "group|g=s"            => \( $opt{ group } = "" ),
    "daemon|d"             => \( $opt{ daemon } = 0 ),
    "kill|k"               => \( $opt{ kill } = 0 ),
    "reload|rk"            => \( $opt{ reload } = 0 ),
    "train-spam=s"         => \( $opt{ train_spam } = "" ),
    "train-ham=s"          => \( $opt{ train_ham } = "" ),
    "train-move=s"         => \( $opt{ train_move } = "" ),
    "train-remove"         => \( $opt{ train_remove } = 0 ),
);

# print help and exit
die <<HELP if $opt{ help };

Usage: $0 --class <classname> --config <configfile> --pidfile <pidfile>

    --class | -a <doorman|detective>
        What kind of server to start ?
            doorman = Mail::Decency::Doorman
            detective = Mail::Decency::Detective
            log-parser = Mail::Decency::LogParser
    
    --config | -c <file>
        Path to config .. 
        default: /etc/decency/<class>.yml
    
    --pid-file | -p <file>
        default: /tmp/<class>.pid
    
    --log-level | -l <1..6>
        the smaller the less verbose and vice versa, overwrite settings
        in the config
    
    --user | -u <uid | user name>
        change to this user
    
    --group | -g <gid | group name>
        change to this user
    
    --daemon | -d
        change to this user
    
    --kill | -k
        kill the server and all child processes
    
    --reload | -r
        Reload configuration
    
    --port <int>
        optional port, overwrites the port settings in config
    
    --host <inet address>
        optional host address, overwrites the host settings in config
    
    --check | -x
        Check wheter running. Exits with 0 if OK, with 1 if not running
        at all and 2 if missing processes are found
    
    --maintenance
        Run in maintenance mode and exit
        This cleans up databases and so on
    
    --print-stats
        Print statistics and exit
    
    --print-sql
        Print SQL "CREATE *" statements in SQLite syntax
    
    --check-db-structure
        Check wheter database structure is good
    
    --upgrade-db-structure
        Check database structure and tries to upgrade if required (eq create
        indexes and tables)
    
    --export <path>
        Exports all stored data in either a gziped tararchive or
        to STDOUT ("-")
    
    --import <path>
        Imports exported databases back to decency.
    
    --import-replace
        Performces a replacive import which will remove all existing data
        before. Default is additive.
    
    --train-(spam|ham) <files>
        For Detective only. Provide a list of files (eg /tmp/spam/*) which will
        then be passed to the training methods of the enabled spam filters.
    
    --train-move <dir>
        Move file after training here
    
    --train-remove
        Delete file after training
    
    --help | -h
        this help

HELP

# check required parameters
die "Provide --class <doorman|detective>\n"
    unless $opt{ class } && $opt{ class } =~ /^(?:doorman|detective)$/;

# switch user / group
( $opt{ user }, $opt{ group } ) = switch_user_group( $opt{ user }, $opt{ group } );

# if config default, replace variable with class
$opt{ config } = sprintf( $opt{ config }, $opt{ class } )
    if $opt{ config } =~ /\%s/;

# cannot read from config
die "Can't read from doorman config file: $opt{ config }\n"
    unless -f $opt{ config };

# assure we have any pid file
$opt{ pid } ||= "/tmp/$opt{ class }.pid";

# use class
my %map = qw/
    doorman    Doorman
    detective  Detective
/;

# check wheter we can load the server class
my $class = "Mail::Decency::$map{ $opt{ class } }";
eval "use $class; 1" or die "Cannot use load $opt{ class }: $@\n";


# read config
$ENV{ DECENCY_CMD_OPTIONS } = \%opt;
my $config = merged_config( \%opt );

# don't run
$ENV{ DECENCY_NO_CHECK_DATABASE } = 1
    if $opt{ print_sql };

# for now, we are not forked.. but if using daemon, we need to inform POE!
$ENV{ DECENCY_PARENT_IS_FORKED } = 0;

# enable debug log if we don't run in daemon mode
$ENV{ DECENCY_CONSOLE_LOG } = $opt{ daemon } ? 0 : 1;
$ENV{ DECENCY_LOG_LEVEL }   = $opt{ log_level } || 0;

# not server mode ? (training, maintenance, stats, ..)
my $server_mode = ! ( $opt{ maintenance } || $opt{ print_stats } || $opt{ print_sql } || $opt{ export } || $opt{ import } || ( $opt{ class } eq 'detective' && ( $opt{ train_spam } || $opt{ train_ham } ) ) );

# enable console log more beautful, if we run server but no daemon
$ENV{ DECENCY_CONSOLE_LOG_FULL } = ! $server_mode || ( $server_mode && ! $opt{ daemon } && ! $opt{ check } );

# start server
my $dir = dirname( $opt{ config } );
my $server = $class->new( config => $config, config_dir => $dir );
my $required_instances = $config->{ server }->{ instances };

# just kill ?
if ( $opt{ kill } ) {
    start_stop( 1 );
}

# just kill ?
elsif ( $opt{ reload } ) {
    my ( $running, $pid ) = is_running();
    if ( $running ) {
        print "Reloading\n";
        kill USR2 => $pid;
    }
    else {
        print "Not running, start first\n";
    }
}

# check running ?
elsif ( $opt{ check } ) {
    my ( $running, $pid ) = is_running();
    
    # at least running
    if ( $running ) {
        
        # oops, missing childs
        exit 2
            if scalar( get_child_pids( $pid ) ) < $required_instances;
        
        # all ok
        exit 0;
    }
    
    # oops, not runnign!
    exit 1;
}

# perform maintenance
elsif ( $opt{ maintenance } || $opt{ print_stats } || $opt{ print_sql } || $opt{ export } || $opt{ import } || $opt{ check_db_structure } || $opt{ upgrade_db_structure } ) {
    
    # assure console log
    $ENV{ DECENCY_CONSOLE_LOG } = 1;
    
    if ( $opt{ maintenance } ) {
        $server->maintenance;
    }
    
    # print out statistics
    elsif ( $opt{ print_stats } ) {
        $server->print_stats;
    }
    
    # print out statistics
    elsif ( $opt{ print_sql } ) {
        $server->setup( undef, { execute => 0 } );
        $server->print_sql;
    }
    
    # export database to file or STDOUT
    elsif ( $opt{ export } ) {
        $server->export_database( $opt{ export } );
    }
    
    # export database to file or STDOUT
    elsif ( $opt{ check_db_structure } || $opt{ upgrade_db_structure } ) {
        $server->check_structure( $opt{ upgrade_db_structure } );
    }
    
    # print out statistics
    elsif ( $opt{ import } ) {
        my $replacive = $opt{ import_replace } ? 1 : 0;
        $server->import_database( $opt{ import }, { replace => $replacive } );
    }
}

elsif ( $opt{ class } eq 'detective' && ( $opt{ train_spam } || $opt{ train_ham } ) ) {
    
    # train SPAM
    $server->train( {
        spam  => 1,
        files => $opt{ train_spam },
        move   => $opt{ train_move },
        remove => $opt{ train_remove },
    } ) if $opt{ train_spam };
    
    # train HAM 
    $server->train( {
        ham    => 1,
        files  => $opt{ train_ham },
        move   => $opt{ train_move },
        remove => $opt{ train_remove },
    } ) if $opt{ train_ham };
    
}

# just run the server
else {
    
    # assure no proc running
    start_stop( 0 );
    
    # daemon mode ? requires forking away from the console
    if ( $opt{ daemon } ) {
        
        # do the fork
        my $is_parent = fork;
        
        # cannot fork -> not good
        unless ( defined $is_parent ) {
            die "FATAL: Cannot fork: $!\n";
        }
        
        # parent -> bye (detach from console)
        elsif ( $is_parent ) {
            exit 0;
        }
        
        # child -> go on..
        else {
            $ENV{ DECENCY_PARENT_IS_FORKED } = 1; 
            setsid or die "Cannot start new detached session: $!\n";
        }
    }
    
    # write pid
    if ( $opt{ pid } ) {
        open my $fh, '>', $opt{ pid }
            or die "Cannot open pid file '$opt{ pid }' for write: $!\n";
        print $fh $$;
        close $fh;
    }
    
    # run ...
    $server->run;
    
    # remove pid file after going down
    unless ( $server->is_child ) {
        unlink( $opt{ pid } )
            if -f $opt{ pid };
    }
}



sub start_stop {
    my $kill = shift || 0;
    
    # check wheter running
    my ( $running, $pid ) = is_running();
    
    # send kill if found running (and want to restartt) or simply shut down
    if ( $kill || $running ) {
        
        die "Server is not running\n"
            unless $running;
        
        # get child pids
        my @childs = get_child_pids( $pid );
        my @pids = ( $pid, @childs );
        
        # kill them all
        kill "TERM", @pids;
        
        # check for all wheter running .. wait until going down
        eval {
            my $not_killed = 0;
            
            # wait for procs to go down..
            local $SIG{ ALRM } = sub {
                die "Timeout waiting\n";
            };
            
            alarm( 5 * $required_instances );
            
            CHECK_RUNNING:
            while( 1 ) {
                my $running = 0;
                foreach my $p( @pids ) {
                    next unless pid_is_running( $p );
                    $running ++;
                }
                last CHECK_RUNNING unless $running;
                print ".";
                sleep 1;
            }
            
            alarm( 0 );
        };
        
        # try EVEN HARDER to get them down ..
        if ( $@ ) {
            
            KILL_RUNNING:
            foreach ( 0..3 ) {
                my $running = 0;
                foreach my $p( @pids ) {
                    next unless pid_is_running( $p );
                    kill "KILL", $p;
                    print "*";
                    $running++;
                }
                last KILL_RUNNING unless $running;
            }
        }
        
        exit 0 if $kill;
    }
    
    return ( $running, $pid );
}

sub is_running {
    my ( $pid, $running );
    
    # having pid file ? Read it now to get the pid
    if ( -f $opt{ pid } ) {
        open my $fh, '<', $opt{ pid }
            or die "Found pid file at '$opt{ pid }', but cannot open for read: $!\n";
        ( $pid ) = <$fh>;
        chomp $pid;
        close $fh;
        
        # check wheter running
        $running = pid_is_running( $pid ) if $pid;
    }
    
    return ( $running, $pid );
}




exit 0;

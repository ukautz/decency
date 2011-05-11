#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;
use Data::Dumper;
use DummyServer;
use Mail::Decency::Helper::Database;
use Mail::Decency::Helper::Locker;
use POSIX ":sys_wait_h";

my $forks = 5;
my $server;
BEGIN { 
    $server = init_server( 'Doorman' );
    use Test::More tests => 7;
}

my $module = init_module( $server, Greylist => {
    min_interval => 1
} );


# setup test datbase
SETUP_DATABSE: {
    init_database( $module );
    ok( 1, "Setup database" );
}

my $master_pid = $$;
my @pids;
foreach my $fork_num( 1..5 ) {
    my $pid = fork;
    if ( $pid ) {
        push @pids, $pid;
    }
    else {
        $ENV{ NO_DB_CLEANUP } = 1;
        foreach my $idx( 0..9 ) {
            print "$fork_num : $idx\n";
            $module->database->increment( greylist => address => {
                from_address => 'addr-'. $$. '-'. $idx. '@domain.tld',
                ip           => '123.123.123.123',
                to_address   => 'bla@domani.tld',
            }, { last_update => 1 } );
        }
        print "** DONE $fork_num **\n";
        done_testing;
        exit;
    }
}

warn "\n\n** ALL OVER, WAIT **\n\n";
waitpid $_, 0 foreach @pids;
warn "\n\n********************** ** DONE ** **********************\n\n";


my ( $handle, $read ) = $module->database->search_read( greylist => 'address' );
while( my $ref = $handle->$read() ) {
    #print Dumper( $ref );
}
warn "\n\n********************** ** DONE DUMP ** **********************\n\n";

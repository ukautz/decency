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

# we nee a simple server
my $server = init_server( 'Doorman' );

# let's use the greylist module
my $module = init_module( $server, Greylist => {
    min_interval => 1
} );

# setup test datbase
SETUP_DATABSE: {
    init_database( $module );
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
        foreach my $idx( 0..99 ) {
            $module->database->increment( greylist => address => {
                from_address => 'addr-'. $$. '-'. $idx. '@domain.tld',
                ip           => '123.123.123.123',
                to_address   => 'bla@domani.tld',
            }, { last_update => 1 } );
        }
        exit;
    }
}

# wait for all forks
waitpid $_, 0 foreach @pids;

# init tests now (or it will complain)
plan tests => 3;

# read all
my ( $handle, $read ) = $module->database->search_read( greylist => 'address' );

# count all
my $count = 0;
while( my $ref = $handle->$read() ) {
    #print Dumper( $ref );
    $count++;
}

# check counted
ok( $count == 500, "Wrote from 5 forks, each 100 entries" );


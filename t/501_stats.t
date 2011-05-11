#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;
use Data::Dumper;
use DateTime;

my $server;
BEGIN { 
    $server = init_server( 'Doorman', {
        stats => {
            
                # module_results
                # module_performance
            enable => [ qw/
                module_results
                module_performance
                final_state
            / ],
            intervals => [ qw/
                hour
                day
                week
                month
                year
            / ],
            maintenance => {
                stream => '50d',
                intervals => {
                    hour => 336,
                    day => 60,
                    week => 52,
                    month => 24,
                    year => 10
                }
            }
        }
    }, {
        no_db_setup => 1
    } );
    use Test::More tests => 17;
}



my $module1 = init_module( $server, 'DummyDoormanDUNNO' );
my $module2 = init_module( $server, 'DummyDoormanOK' );

#print "CHECK ". $server->check_database( $server->schema_definition ). "\n";;
init_database( $server );
ok( $server->check_database( $server->schema_definition ),
    "Database setup OK" );

my $attrs_ref = {
    client_address => '1.1.1.1',
    sender         => "from\@sender.tld",
    recipient      => "to\@recipient.tld",
};
push @{ $server->childs }, $module1;
push @{ $server->childs }, $module2;
my $handler = $server->get_handlers();
eval {
    $handler->( $server, $attrs_ref );
    $handler->( $server, $attrs_ref );
};

#
# PERFORMANCE
#

my @r1 = $server->database->search( stats => 'doorman_performance' );

# 5 intervals, 2 modules
ok( scalar( @r1 ) == 10, "Doorman performance DB entries" );

# we ran 2 times
ok( scalar( grep { $_->{ calls } == 2 } @r1 ) == 10, "Doorman performance DB calls" );

# 5 times for each module
ok( scalar( grep { $_->{ module } eq 'DummyDoormanDUNNO' } @r1 ) == 5
    && scalar( grep { $_->{ module } eq 'DummyDoormanOK' } @r1 ) == 5, 
    "Doorman performance DB modules"
);

# last update looks good
ok( scalar( grep { $_->{ last_update } <= time() } @r1 ) == 10,
    "Doorman performance DB update time" );

# period looks good
my $dt = DateTime->now( time_zone => 'local' );
ok( scalar( grep {
    $_->{ start } == $dt->clone->truncate( to => $_->{ period } )->epoch
    || $_->{ start } == $dt->clone->add( $_->{ period }.'s' => -1 )
        ->truncate( to => $_->{ period } )->epoch
} @r1 ) == 10, "Doorman performance DB interval start" );


#
# RESULTS
#

my @r2 = $server->database->search( stats => 'doorman_results' );

# 5 intervals, 2 states
ok( scalar( @r2 ) == 10, "Doorman results DB entries" );

# we ran 2 times
ok( scalar( grep { $_->{ calls } == 2 } @r2 ) == 10, "Doorman results DB calls" );

# 5 times for each state
ok( scalar( grep { $_->{ status } eq 'DUNNO' } @r2 ) == 5
    && scalar( grep { $_->{ status } eq 'OK' } @r2 ) == 5, 
    "Doorman results DB states"
);

# last update looks good
ok( scalar( grep { $_->{ last_update } <= time() } @r2 ) == 10,
    "Doorman results DB update time" );

# period looks good
my $dt = DateTime->now( time_zone => 'local' );
ok( scalar( grep {
    $_->{ start } == $dt->clone->truncate( to => $_->{ period } )->epoch
    || $_->{ start } == $dt->clone->add( $_->{ period }.'s' => -1 )
        ->truncate( to => $_->{ period } )->epoch
} @r2 ) == 10, "Doorman results DB interval start" );

my @r3 = $server->database->search( stats => 'doorman_final_state' );

# 5 intervals, all pass
ok( scalar( @r3 ) == 5, "Doorman final state DB entries" );

# we ran 2 times
ok( scalar( grep { $_->{ amount } == 2 } @r3 ) == 5, "Doorman final state DB calls" );

# we ran 2 times
ok( scalar( grep { $_->{ status } eq 'ok' } @r3 ) == 5, "Doorman final state DB state" );

# period looks good
my $dt = DateTime->now( time_zone => 'local' );
ok( scalar( grep {
    $_->{ start } == $dt->clone->truncate( to => $_->{ period } )->epoch
    || $_->{ start } == $dt->clone->add( $_->{ period }.'s' => -1 )
        ->truncate( to => $_->{ period } )->epoch
} @r3 ) == 5, "Doorman final state DB interval start" );



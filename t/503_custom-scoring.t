#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_DB;
use MD_Misc;
use Data::Dumper;


my $server;
BEGIN { 
    $server = init_server( 'Doorman', {
        custom_scoring => {
            database => 1
        }
    } );
    use Test::More tests => 6;
}


my $module = init_module( $server, 'DummyDoormanCUSTOMSCORING', {
    score => -20
} );

# setup test datbase
SETUP_DATABSE: {
    init_database( $server );
    ok( 1, "Setup database" );
}

$server->database->set( custom_scoring => lc( $server->name ) => {
    recipient => 'domain1.tld',
    value     => -10
} );

$server->database->set( custom_scoring => lc( $server->name ) => {
    recipient => 'domain2.tld',
    value     => -30
} );

$server->database->set( custom_scoring => lc( $server->name ) => {
    recipient => 'special@domain1.tld',
    value     => -30
} );

# those simulate postfix attributes
my $attrs_ref = {
    client_address => '255.255.0.0',
    sender         => 'doesnt@matter.tld',
    recipient      => 'recipient@domain1.tld'
};

session_init( $server, $attrs_ref );
eval {
    $module->handle();
};
ok_for_reject( $server, $@, "Lower threshold domain" );

$attrs_ref->{ recipient } = 'someone@domain.tld';
session_init( $server, $attrs_ref );
eval {
    $module->handle();
};
ok_for_dunno( $server, $@, "Higher threshold domain" );

$attrs_ref->{ recipient } = 'special@domain1.tld';
session_init( $server, $attrs_ref );
eval {
    $module->handle();
};
ok_for_dunno( $server, $@, "Higher threshold address" );

$attrs_ref->{ recipient } = 'recipient@other.tld';
session_init( $server, $attrs_ref );
eval {
    $module->handle();
};
ok_for_dunno( $server, $@, "No custom threshold" );



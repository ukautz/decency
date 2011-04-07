#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Policy' );
    use Test::More tests => 11;
}

my $module = init_module( $server, Throttle => {} );


# setup test datbase
SETUP_DATABSE: {
    
    # add for bigger limit exception
    $module->database->set( throttle => sender_domain => {
        sender_domain => 'biglimit.tld',
        maximum       => 10,
        interval      => 600
    } );
    
    # add for account test
    $module->database->set( throttle => sender_domain => {
        sender_domain => 'accounttest.tld',
        maximum       => -1, # infinite
        interval      => 600,
        account       => 'some-account'
    } );
    $module->database->set( throttle => account => {
        account  => 'some-account',
        maximum  => 1,
        interval => 600,
    } );
    
    ok( 1, "Setup database" );
}


# setup test datbase
TEST_DEFAULT: {
    
    # build data for test
    my $attrs_ref = {
        sender  => 'bla@defaultsender.tld',
    };
    session_init( $server, $attrs_ref );
    
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "First send passwd" );
    
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Second send passed" );
    
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "Third send denied" );
    
    $attrs_ref = {
        sender  => 'bla@other-sender.tld',
    };
    session_init( $server, $attrs_ref );
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Other sender pass" );
    
    
}


# setup test datbase
TEST_EXCEPTIONS: {
    
    # build data for test
    my $attrs_ref = {
        sender  => 'bla@biglimit.tld',
    };
    session_init( $server, $attrs_ref );
    eval {
        $module->handle() for ( 0 .. 9 );
    };
    ok_for_dunno( $server, $@, "Exception for domain: pass" );
    
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "Exception for domain: reject" );
    
}


# setup test datbase
TEST_ACCOUNT: {
    
    # build data for test
    my $attrs_ref = {
        sender  => 'bla@accounttest.tld',
    };
    session_init( $server, $attrs_ref );
    eval {
        $module->handle() for 1;
    };
    ok_for_dunno( $server, $@, "Account domain: pass" );
    
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "Account domain: reject" );
    
}







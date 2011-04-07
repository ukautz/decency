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
    use Test::More tests => 6;
}

my $cwl = init_module( $server, CWL => {
    activate_sender_list    => 1,
    activate_recipient_list => 1,
}, {
    name => "TestCWL"
} );

my $cbl = init_module( $server, CBL => {
    activate_sender_list    => 1,
    activate_recipient_list => 1,
}, {
    name => "TestCBL"
} );

foreach my $ref( [ cwl => $cwl, \&ok_for_ok ], [ cbl => $cbl, \&ok_for_reject ] ) {
    my ( $name, $module, $test ) = @$ref;
    subtest uc( $name ) => sub {
        plan tests => 9;
        run_test( $module, $name, $test );
    };
}


sub run_test {
    my ( $module, $name, $test ) = @_;
    
    # insert data
    CREATE_RECORDS: {
        eval {
            $module->database->set( $name => ips => {
                ip        => '255.255.0.0',
                to_domain => 'dummy1.tld',
            } );
            $module->database->set( $name => domains => {
                from_domain => 'dummy2.tld',
                to_domain   => 'dummy1.tld',
            } );
            $module->database->set( $name => addresses => {
                from_address => 'someone@dummy3.tld',
                to_domain    => 'dummy1.tld',
            } );
            $module->database->set( $name => ips => {
                ip        => '123.123.123.123',
                to_domain => '*',
            } );
            $module->database->set( $name => domains => {
                from_domain => 'allallowed.tld',
                to_domain   => '*',
            } );
            $module->database->set( $name => addresses => {
                from_address => 'all@allowed.tld',
                to_domain    => '*',
            } );
            $module->database->set( $name => domains => {
                from_domain => '*',
                to_domain   => 'allgood.tld',
            } );
        };
        ok( !$@, "Test records inserted" ) or die( "Problem: $@" );
    }
    
    
    
    my $attrs_ref = {
        sender_address    => 'someone@somewhere.com',
        sender_domain     => 'somewhere.com',
        recipient_address => 'test@dummy1.tld',
        recipient_domain  => 'dummy1.tld',
        client_address    => '255.255.0.1',
    };
    
    # check negative
    CHECK_NEGATIVE: {
        session_init( $server, $attrs_ref );
        eval {
            $module->handle( undef, $attrs_ref );
        };
        ok_for_dunno( $server, $@, "DUNNO for unknown" );
    }
    
    
    # check IP
    CHECK_IP: {
        my $positive_ref = { %$attrs_ref, client_address => '255.255.0.0' };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "IP listing" );
    }
    
    
    
    # check DOMAIN
    CHECK_DOMAIN: {
        my $positive_ref = {
            %$attrs_ref,
            sender_domain  => 'dummy2.tld',
            sender_address => 'somewhere@dummy2.tld',
        };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "Domain listing" );
    }
    
    
    
    # check ADDRESS
    CHECK_ADDRESS: {
        my $positive_ref = {
            %$attrs_ref,
            sender_domain  => 'dummy3.tld',
            sender_address => 'someone@dummy3.tld'
        };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "Address listing" );
    };
    
    
    
    # check SENDER LIST
    CHECK_SENDER_LIST: {
        my $positive_ref = {
            %$attrs_ref,
            client_address => '123.123.123.123'
        };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "Sender ip list" );
        
        
        $positive_ref = {
            %$attrs_ref,
            sender_domain  => 'allallowed.tld',
            sender_address => 'someone@allallowed.tld'
        };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "Sender domain list" );
        
        
        $positive_ref = {
            %$attrs_ref,
            sender_domain  => 'allowed.tld',
            sender_address => 'all@allowed.tld'
        };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "Sender address list" );
    };
    
    
    
    # check RECIPIENT LIST
    CHECK_RECIPIENT_LIST: {
        my $positive_ref = {
            %$attrs_ref,
            recipient_address => 'test@allgood.tld',
            recipient_domain  => 'allgood.tld',
        };
        session_init( $server, $positive_ref );
        eval {
            $module->handle( undef, $positive_ref );
        };
        $test->( $server, $@, "Recipient list" );
    };
}








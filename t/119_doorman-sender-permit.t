#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Doorman' );
    use Test::More tests => 9;
}

my $module = init_module( $server, SenderPermit => {} );



# insert data
CREATE_RECORDS: {
    eval {
        $module->database->set( sender => permit => {
            from_domain => 'sender1.tld',
            to_domain   => 'recipient1.tld',
            fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:01',
            subject     => '1.porcupine.org',
            ip          => '123.123.123.1',
        } );
        $module->database->set( sender => permit => {
            from_domain => 'sender2.tld',
            to_domain   => 'recipient2.tld',
            fingerprint => '*',
            subject     => '*',
            ip          => '123.123.123.2',
        } );
        $module->database->set( sender => permit => {
            from_domain => 'sender3.tld',
            to_domain   => '*',
            fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:02',
            subject     => '2.porcupine.org',
            ip          => '123.123.123.3',
        } );
        $module->database->set( sender => permit => {
            from_domain => 'sender4.tld',
            to_domain   => '*',
            fingerprint => '*',
            subject     => '*',
            ip          => '123.123.123.4',
        } );
        $module->database->set( sender => permit => {
            from_domain => 'sender5.tld',
            to_domain   => '*',
            fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:03',
            subject     => '3.porcupine.org',
            ip          => '*',
        } );
    };
    ok( !$@, "Test records inserted" ) or die( "Problem: $@" );
}


# build data for test
my @attrs = ( [ 'strict channel', {
    sender            => 'sd@sender1.tld',
    recipient         => 'rcp@recipient1.tld',
    ccert_fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:01',
    ccert_subject     => '1.porcupine.org',
    client_address    => '123.123.123.1',
} ], [ 'loose channel', {
    sender            => 'sd@sender2.tld',
    recipient         => 'rcp@recipient2.tld',
    ccert_fingerprint => '',
    ccert_subject     => '',
    client_address    => '123.123.123.2',
} ], [ 'strict relaying', {
    sender            => 'sd@sender3.tld',
    recipient         => 'rcp@recipient3.tld',
    ccert_fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:02',
    ccert_subject     => '2.porcupine.org',
    client_address    => '123.123.123.3',
} ], [ 'loose ip based relaying', {
    sender            => 'sd@sender4.tld',
    recipient         => 'rcp@recipient4.tld',
    ccert_fingerprint => '',
    ccert_subject     => '',
    client_address    => '123.123.123.4',
} ], [ 'loose cert based realying', {
    sender            => 'sd@sender5.tld',
    recipient         => 'rcp@recipient5.tld',
    ccert_fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:03',
    ccert_subject     => '3.porcupine.org',
    client_address    => '123.123.123.5',
} ] );


# setup test datbase
TEST_CORRECT: {
    
    foreach my $ref( @attrs ) {
        my ( $name, $attrs_ref ) = @$ref;
        session_init( $server, $attrs_ref );
        
        $server->session->spam_score( 0 );
        eval {
            $module->handle();
        };
        ok( ! $@ && $server->session->response eq 'OK', "Allow $name" );
    }
}


TEST_FAIL: {
    session_init( $server, {
        sender            => 'sd@sender6.tld',
        recipient         => 'rcp@recipient6.tld',
        ccert_fingerprint => 'C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:04',
        ccert_subject     => '6.porcupine.org',
        client_address    => '123.123.123.6',
    } );
    $server->session->spam_score( 0 );
    eval {
        $module->handle();
    };
    ok( ! $@ && $server->session->response eq 'DUNNO', "Permission not granted" );
}





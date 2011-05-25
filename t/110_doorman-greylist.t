#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;
no warnings 'once';

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

my $sender_domain    = 'dummy1.tld';
my $sender           = 'sender-'. time(). '@'. $sender_domain;
my $recipient_domain = 'dummy2.tld';
my $recipient        = 'recipient-'. time(). '@'. $recipient_domain;

# those simulate postfix attributes
my $attrs_ref = {
    client_address => '255.255.0.0',
    sender         => "${sender}\@${sender_domain}",
    recipient      => "${recipient}\@${recipient_domain}",
};

# first pass: should throw Mail::Decency::Core::Exception::Reject
FIRST_PASS: {
    session_init( $server, $attrs_ref );
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "First pass: reject" );
}

# wait a second until we are allowed to pass
sleep 1;

# second pass: should throw no erro but allow
SECOND_PASS: {
    session_init( $server, $attrs_ref );
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Second pass: passed" );
}

# wait a second until we are allowed to pass
sleep 2;


ADDITIONAL_PASS: {
    foreach ( 0..1 ) {
        session_init( $server, $attrs_ref );
        eval {
            $module->handle();
        };
    }
    
    my %attr = ( %$attrs_ref, recipient => 'recipient2-'. time(). '@'. $recipient_domain );
    session_init( $server, \%attr );
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Different recipient at same domain: passed" );
    
    
    session_init( $server, $attrs_ref );
    eval {
        $module->handle();
    };
    
    $attr{ sender } = 'sender2-'. time(). '@'. $sender_domain;
    session_init( $server, \%attr );
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Different sender from sender domain: passed" );
}




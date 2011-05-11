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
    use Test::More tests => 5;
}


skip "Net::DNSBL::Client not installed, skipping tests", 3
    unless eval "use Net::DNSBL::Client; 1;";

my $module = init_module( $server, DNSBL => {} );


my $attrs_ref = {
    client_address    => '127.0.0.1',
    sender_address    => 'sender@domain.tld',
    recipient_address => 'recipient@domain.tld',
};


# check negative
CHECK_NEGATIVE: {
    session_init( $server, $attrs_ref );
    eval {
        $module->handle( undef, $attrs_ref );
    };
    ok_for_dunno( $server, $@, "No hit on 127.0.0.1" );
    ok( 
        $server->session->spam_details_str( ' / ' ) eq 'Module: Test; Score: 0'
        && $server->session->message_str( ' / ' ) eq '',
        'Message and details for no hit'
    );
}

# check positive
CHECK_POSITIVE: {
    $attrs_ref->{ client_address } = '127.0.0.2';
    session_init( $server, $attrs_ref );
    eval {
        $module->handle( undef, $attrs_ref );
    };
    ok_for_reject( $server, $@, "Always hit on 127.0.0.2" );
    ok( 
        $server->session->spam_details_str( ' / ' ) eq 'Module: Test; Score: -100; Blacklisted on: ix.dnsbl.manitu.net'
        && $server->session->message_str( ' / ' ) eq 'Blacklisted on: ix.dnsbl.manitu.net',
        'Message and details for hit'
    );
}





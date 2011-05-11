#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Detective' );
    use Test::More tests => 3;
}

my $module = init_module( $server, DeepDNSBL => {
} );

IS_BLACKLISTED: {
    session_init( $server );
    $server->session->ips( [ '127.0.0.2' ] );
    eval {
        $module->handle();
    };
    ok( $module->session->spam_score == -100, "DNSBL hit" );
}

NOT_BLACKLISTED: {
    session_init( $server );
    $server->session->ips( [ '127.0.0.1' ] );
    eval {
        $module->handle();
    };
    ok( $module->session->spam_score == 0, "No DNSBL hit" );
}



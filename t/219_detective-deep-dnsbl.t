#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


eval 'use Net::DNSBL::Client; 1;'
    || plan skip_all => 'Module "Net::DNSBL::Client" not installed';

my $server = init_server( 'Detective' );
plan tests => 3;

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



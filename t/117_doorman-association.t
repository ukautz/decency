#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


plan skip_all => "Net::Netmask not installed, skipping tests"
    unless eval "use Net::Netmask; 1;";
plan skip_all =>  "Net::Domain::TLD not installed, skipping tests"
    unless eval "use Net::Domain::TLD; 1;";

my $server = init_server( 'Doorman' );
plan tests => 4;

my $module = init_module( $server, Association => {} );


TEST_MX: {
    
    my ( $mx_ok ) =
        map { $_->exchange }
        Net::DNS::Resolver->new->query( 'gmx.net', 'MX' )->answer
    ;
    my ( $mx_ip ) =
        map { $_->address }
        Net::DNS::Resolver->new->query( $mx_ok, 'A' )->answer
    ;
    
    # build data for test
    my $attrs_ref = {
        client_address => $mx_ip,
        sender         => 'test@gmx.net'
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle();
    };
    ok( ! $@ && $weight_before < $server->session->spam_score, "MX recognized" );
}


TEST_A: {
    
    my ( $a_ip ) =
        map { $_->address }
        Net::DNS::Resolver->new->query( 'gmx.net', 'A' )->answer
    ;
    # build data for test
    my $attrs_ref = {
        client_address => $a_ip,
        sender         => 'test@gmx.net'
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle();
    };
    ok( ! $@ && $weight_before < $server->session->spam_score, "A recognized" );
}




TEST_WRONG_A: {
    
    my ( $a_ip ) =
        map { $_->address }
        Net::DNS::Resolver->new->query( 'google.com', 'A' )->answer
    ;
    # build data for test
    my $attrs_ref = {
        client_address => $a_ip,
        sender         => 'test@gmx.net'
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle();
    };
    ok( $weight_before > $server->session->spam_score, "Wrong IP recognized" );
}







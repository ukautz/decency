#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use MIME::QuotedPrint;
use Data::Dumper;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;

my $server;
BEGIN { 
    $server = init_server( 'Policy' );
    use Test::More tests => 12;
}

ok( $server, "Policy Server loaded" );

SESSION_INIT: {
    eval {
        session_init( $server );
    };
    ok( !$@, "Session created" )
        or fail( "Failed to create session: $@" );
}

RECIPIENT_DELIMITER: {
    eval {
        $server->recipient_delimiter( '+' );
        session_init( $server, {
            recipient_address => 'test+123@test.tld'
        } );
    };
    ok( !$@, 'SO FAR' )
        or fail( "ARR: $@" );
    ok( 1, "Session created" )
        or fail( "Failed to create session: $@" );
    $server->recipient_delimiter( '' );
}

CHECK_THROW_REJECT: {
    session_init( $server );
    eval {
        $server->go_final_state( Dummy => 'REJECT' );
    };
    ok_for_reject( $server, $@, "Reject throws error" );
}


CHECK_THROW_OK: {
    session_init( $server );
    eval {
        $server->go_final_state( Dummy => 'OK' );
    };
    ok_for_ok( $server, $@, "OK throws error" );
}


CHECK_PASSING: {
    session_init( $server );
    eval {
        $server->go_final_state( Dummy => 'DUNNO' );
    };
    ok_for_dunno( $server, $@, "Dunno passes" );
}

CHECK_FINAL: {
    session_init( $server );
    eval {
        $server->session->add_message( "THE REASON 123" );
        $server->go_final_state( Dummy => 'REJECT' );
    };
    my $res = decode_qp( $server->session_cleanup );
    ok( $res =~ /^REJECT THE REASON 123 \[[a-z0-9]+\]$/, "Response message injection" );
}


CHECK_SPAM_SCORE: {
    session_init( $server );
    $server->add_spam_score( M1 => 123 );
    $server->add_spam_score( M2 => -23 );
    my $res = decode_qp( $server->session_cleanup );
    my @res = split( /\|/, $res );
    ok( $res[0] =~ /^PREPEND X-Decency-Instance/, "Prepend generated" );
    ok( $res[2] eq '100', "Weighting appended" );
    ok( $res[5] eq 'Module: M1; Score: 123' && $res[6] eq 'Module: M2; Score: -23', "Info appended" );
}

CHECK_FLAGS: {
    session_init( $server );
    $server->session->set_flag( 'test' );
    $server->session->set_flag( 'xxx' );
    my $res = decode_qp( $server->session_cleanup );
    my @res = split( /\|/, $res );
    ok( $res[4] eq 'test,xxx', "Flag appended" );
}


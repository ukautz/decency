#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;

my $server;
BEGIN { 
    $server = init_server( 'ContentFilter' );
    use Test::More tests => 5;
}

ok( 1, "ContentFilter Server loaded" );

SESSION_INIT: {
    eval {
        session_init( $server );
    };
    ok( !$@, "Session created" )
        or fail( "Failed to create session: $@" );
}


ADD_SPAM_DETAILS: {
    my $spam_details = '';
    eval {
        session_init( $server );
        $server->add_spam_score( -10, Dummy => "Some SPAM Detail" );
        $spam_details = $server->session->spam_details_str( ' / ' );
    };
    ok(
        $spam_details eq 'Module: Dummy; Score: -10; Some SPAM Detail',
        "Add spam details"
    );
}


CHECK_MIME_HEADER: {
    eval {
        use Data::Dumper;
        session_init( $server );
        $server->add_spam_score( 123, Dummy => "Some Detail" );
        $server->finish( 'ongoing' );
    };
    ok(
        ! $@ 
        && $server->session->mime_header( get => 'X-Decency-Result' ) eq "GOOD\n"
        && $server->session->mime_header( get => 'X-Decency-Score' ) eq "123\n"
        && $server->session->mime_header( get => 'X-Decency-Details' ) eq "Module: Dummy; Score: 123; Some Detail\n",
        "MIME Header"
    );
}


CHECK_VIRUS: {
    eval {
        session_init( $server );
        $server->found_virus( "Some Virus" );
    };
    ok( $@ && "$@" eq "Virus found: Some Virus", "Trigger exception on Virus" );
}



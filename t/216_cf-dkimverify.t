#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'ContentFilter' );
    use Test::More tests => 5;
}

SKIP: {

    skip "Mail::DKIM::Verifier not installed, skipping tests", 3
        unless eval "use Mail::DKIM::Verifier; 1;";
    
    my $module = init_module( $server, DKIMVerify => {} );
    
    session_init( $server, "$Bin/sample/eml/dkim-invalid.eml" );
    eval {
        $module->handle();
    };
    ok( $module->session->spam_score == -22, "Invalid recognized" );
    
    session_init( $server, "$Bin/sample/eml/dkim-pass.eml" );
    eval {
        $module->handle();
    };
    ok( $module->session->spam_score == 44, "Pass recognized" );
    
    session_init( $server, "$Bin/sample/eml/dkim-fail.eml" );
    eval {
        $module->handle();
    };
    ok( $module->session->spam_score == -11, "Fail recognized" );
    
    session_init( $server );
    eval {
        $module->handle();
    };
    ok( $module->session->spam_score == 7, "None recognized" );
}




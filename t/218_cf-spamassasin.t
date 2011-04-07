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
    use Test::More tests => 4;
}

SKIP: {
    
    $ENV{ SPAMASSASSIN_LIB } && eval "use lib '$ENV{ SPAMASSASSIN_LIB }';";
    
    skip "Mail::SpamAssassin::Client not installed, skipping tests", 4
        unless eval "use Mail::SpamAssassin::Client; 1;";
    
    ok( eval "use Mail::Decency::ContentFilter::SpamAssassin; 1;", "Loaded Mail::Decency::ContentFilter::SpamAssassin" )
        or die "could not load: Mail::Decency::ContentFilter::SpamAssassin";

    skip "dspam test, enable with USE_SPAMASSASSIN=1 and set optional SPAMASSASSIN_USER for the tests (default: \$ENV{ USER })", 3
        unless $ENV{ USE_SPAMASSASSIN };
    
    my $module = init_module( $server, SpamAssassin => {
        default_user => $ENV{ SPAMASSASSIN_USER } || $ENV{ USER }
    } );
    session_init( $server );
        
    FILTER_TEST: {
        eval {
            $module->handle();
        };
        my $spam_details = $server->session->spam_details_str( '; ' );
        
        ok(
            ! $@ && scalar @{ $server->session->spam_details } == 1,
            "Filter result found"
        );
        
        ok(
            $spam_details =~ /^Module: Test; Score: 10; Status: [^,]+, score=[0-9\.]+ required=[0-9\.]+ tests=[A-Z0-9_,]+/,
            "SpamAssassin filter used"
        );
    }
}



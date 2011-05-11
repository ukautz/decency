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

my $module = init_module( $server, DSPAM => {
    default_user => $ENV{ DSPAM_USER } || 'global_shared'
} );

SKIP: {
    
    chomp( my $dspam = $ENV{ CMD_DSPAM } || `which dspam` );
    skip "could not find dpsam executable. Provide via CMD_DSPAM in Env or set correct PATH", 2
        unless $dspam && -x $dspam;
    skip "dspam test, enable with USE_DSPAM=1 and set optional DSPAM_USER for the tests (default: global_shared)", 2
        unless $ENV{ USE_DSPAM };
    
    
    
    FILTER_TEST: {
        session_init( $server );
        
        eval {
            $module->handle();
        };
        
        ok(
            ! $@ && scalar @{ $server->session->spam_details } == 1,
            "Filter result found"
        );
        
        ok(
            $server->session->spam_details->[0] =~ /DSPAM result: (innocent|spam)/,
            "DSPAM filter used"
        );
    }
}



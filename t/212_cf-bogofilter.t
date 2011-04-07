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
    use Test::More tests => 3;
}

my $module = init_module( $server, Bogofilter => {} );

SKIP: {
    
    chomp( my $bogofilter = $ENV{ CMD_BOGOFILTER } || `which bogofilter` );
    skip "could not find bogofilter executable. Provide via CMD_BOGOFILTER in Env or set correct PATH", 2
        unless $bogofilter && -x $bogofilter;
    skip "BOGOFILTER test, enable with USE_BOGOFILTER=1 and set optional BOGOFILTER_USER for the tests (default: global_shared)", 2
        unless $ENV{ USE_BOGOFILTER };
    
    # set check command..
    $module->cmd_check( "$bogofilter --user-config-file \%user\% -U -I \%file\% -v" );
    
    
    FILTER_TEST: {
        session_init( $server );
        
        eval {
            my $res = $module->handle();
        };
        
        ok(
            ! $@ && scalar @{ $server->session->spam_details } == 1,
            "Filter result found"
        );
        
        ok(
            $server->session->spam_details->[0] =~ /Bogofilter status: (ham|spam|unsure)/,
            "Bogofilter filter used"
        );
    }
};



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

SKIP: {
    
    skip "RAZOR test, enable with USE_RAZOR=1 and set optional CMD_RAZOR for the tests (default: /usr/bin/razor-check)", 3
        unless $ENV{ USE_RAZOR };
    
    chomp( my $razor = $ENV{ CMD_RAZOR } || `which razor-check` || '/usr/bin/razor-check' );
    skip "could not find mailreaver.crm executable. Provide via CMD_RAZOR in Env or set correct PATH", 3
        unless $razor && -x $razor;
    
    my $module = init_module( $server, Razor => {} );
    
    # set check command..
    $module->cmd_check( "$razor \%file\%" );
    
    
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
            $server->session->spam_details->[0] =~ /Module: Test; Score: 10; This is (HAM|SPAM)/,
            "Razor filter used"
        ) or diag( "Wrong answer: ". $server->session->spam_details->[0] );
    }
}



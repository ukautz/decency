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

SKIP: {
    

    chomp( my $crm114 = $ENV{ CMD_CRM114 } || `which mailreaver.crm` || '/usr/share/crm114/mailreaver.crm' );
    skip "could not find mailreaver.crm executable. Provide via CMD_CRM114 in Env or set correct PATH", 3
        unless $crm114 && -x $crm114;
    skip "CRM114 test, enable with USE_CRM114=1 and set optional CRM114_USER for the tests (default: /etc/crm114)", 3
        unless $ENV{ USE_CRM114 };
    
    my $module = init_module( $server, CRM114 => {
        default_user => $ENV{ CRM114_USER } || '/etc/crm114'
    } );
    
    
    # set check command..
    $module->cmd_check( "$crm114 -u \%user\%" );
    
    
    FILTER_TEST: {
        session_init( $server );
        
        eval {
            my $res = $module->handle();
        };
        $@ && diag( "Error: $@" );
        ok(
            ! $@ && scalar @{ $server->session->spam_details } == 1,
            "Filter result found"
        );
        
        ok(
            $server->session->spam_details->[0] =~ /CRM114 status: (good|spam|unsure)/,
            "CRM114 filter used"
        );
    }
}



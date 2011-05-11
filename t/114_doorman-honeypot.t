#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Doorman' );
    use Test::More tests => 14;
}

my $module = init_module( $server, Honeypot => {} );


# create records
CREATE_RECORDS: {
    eval {
        $module->database->set( honeypot => ips => {
            ip => '192.168.1.1',
        }, {
            created => time()
        } );
    };
    ok( !$@, "Database records created" ) or diag( "Problem: $@" );
}



# check wheter not associated sender passes
CHECK_NEGATIVE: {
    my %attrs = (
        client_address => '192.168.1.2',
        recipient      => 'someone@recipient.tld',
    );
    session_init( $server, \%attrs );
    
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Unlisted passes" );
}



# check a single address which should ne listed
CHECK_ADDRESS: {
    
    # get the recipient
    my $fail_recipient = $module->config->{ addresses }->[0];
    my ( $prefix, $domain ) = split( /\@/, $fail_recipient, 2 );
    
    my %attrs = (
        client_address => '192.168.1.3',
        recipient      => "${prefix}\@${domain}",
    );
    session_init( $server, \%attrs );
    
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "Reject for listed recipient address" );
}



# check a listed domain
CHECK_DOMAIN: {
    # get the recipient
    my $fail_domain = $module->config->{ domains }->[0];
    
    my %attrs = (
        client_address => '192.168.1.4',
        recipient      => "xxx\@$fail_domain",
    );
    session_init( $server, \%attrs );
    
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "Reject for listed recipient domain" );
}



# check a listed domain
CHECK_DOMAIN_EXCEPTIONS: {
    
    # get the recipient
    my $fail_domain_ref  = $module->config->{ domains }->[1];
    my $fail_domain      = $fail_domain_ref->{ domain };
    my $exception_prefix = $fail_domain_ref->{ exceptions }->[0];
    my $other_prefix     = $exception_prefix. "-other";
    
    CHECK_REJECTED: {
        my %attrs = (
            client_address => '192.168.1.5',
            recipient      => "$other_prefix\@$fail_domain"
        );
        session_init( $server, \%attrs );
        
        eval {
            $module->handle();
        };
        ok_for_reject( $server, $@, "Reject for listed recipient exception domain, non exception recipient" );
    }
    
    
    CHECK_PASS: {
        my %attrs = (
            client_address => '192.168.1.6',
            recipient      => "$exception_prefix\@$fail_domain"
        );
        session_init( $server, \%attrs );
        
        eval {
            $module->handle();
        };
        ok_for_dunno( $server, $@, "Pass for listed recipient exception domain, with exception recipient" );
        
    }
}







# check a listed domain
CHECK_PASS_FLAG: {
    
    # get the recipient
    my $fail_domain = $module->config->{ domains }->[0];
    
    my $module = init_module( $server, Honeypot => {
        pass_for_collection => 1
    } );
    
    ok( $module && $module->pass_for_collection, "Honeypot with pass_for_collection loaded" );
    
    my %attrs = (
        client_address => '192.168.1.7',
        recipient      => "xxx\@$fail_domain"
    );
    session_init( $server, \%attrs );
    
    eval {
        $module->handle();
    };
    ok_for_prepend( $server, $@, "Collected recipient domain passed flawlessy" );
    
    ok( defined $server->session->has_flag( 'honey' ), "Flag passed" );
}



# check now wheter all are in database whou should be!
CHECK_RECORDS: {
    eval {
        foreach my $ip( qw/ 1 3 4 5 7 / ) {
            my $found = $module->database->get( honeypot => ips => {
                ip => '192.168.1.'. $ip,
            } );
            die "Not found in database: 192.168.1.$ip\n" unless $found;
        }
        foreach my $ip( qw/ 2 6 / ) {
            my $found = $module->database->get( honeypot => ips => {
                ip => '192.168.1.'. $ip,
            } );
            die "Found falsly in database: 192.168.1.$ip\n" if $found;
        }
    };
    ok( !$@, "Database records are valid" ) or diag( "Problem: $@" );
    
}







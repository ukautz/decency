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
    use Test::More tests => 7;
}

skip "Email::Valid not installed, skipping tests", 7
    unless eval "use Email::Valid; 1;";

my $module = init_module( $server, Basic => {} );

my ( $mx_ok, $mx_ip );

eval {
    ( $mx_ok ) =
        map { $_->exchange }
        Net::DNS::Resolver->new->query( 'gmx.net', 'MX' )->answer
    ;
    ( $mx_ip ) =
        map { $_->address }
        Net::DNS::Resolver->new->query( $mx_ok, 'A' )->answer
    ;
};
ok( !$@ && $mx_ip, "Resolved testing address" ) or die( "Problem: $@" );

# build data for test
my %attrs = (
    helo_name      => 'gmx.net',
    client_name    => 'gmx.net',
    client_address => $mx_ip,
    sender         => 'sender@gmx.net',
    recipient      => 'ulrich.kautz@googlemail.com',
);


# setup test datbase
TEST_CORRECT: {
    
    my $attrs_ref = { %attrs };
    session_init( $server, $attrs_ref );
    
    $server->session->spam_score( 0 );
    eval {
        $module->handle();
    };
    ok( ! $@ && $server->session->spam_score == 0, "Correct sender, no spamscore" );
}


# setup test datbase
TEST_HELO: {
    
    my $attrs_ref = {
        %attrs,
        helo_name => 'gmx', # correct, but not fqdn and invalid
    };
    session_init( $server, $attrs_ref );
    
    $server->session->spam_score( 0 );
    eval {
        $module->handle();
    };
    my @details = @{ $server->session->spam_details };
    ok( $server->session->spam_score == -10
        && $details[0] eq 'Module: Test; Score: -5; Helo hostname is not in FQDN'
        && $details[1] eq 'Module: Test; Score: -5; Helo hostname is unknown'
        && scalar @details == 3, "No FQDN, Unknown"
    );
    
    
    $attrs_ref = {
        %attrs,
        helo_name => '???', # correct, but not fqdn and invalid
    };
    session_init( $server, $attrs_ref );
    
    $server->session->spam_score( 0 );
    eval {
        $module->handle();
    };
    @details = @{ $server->session->spam_details };
    #print "HERE ". Dumper( [ $server->session->spam_score, @details ] );
    ok( $server->session->spam_score == -15
        && $details[0] eq 'Module: Test; Score: -5; Helo hostname is invalid'
        && $details[1] eq 'Module: Test; Score: -5; Helo hostname is not in FQDN'
        && $details[2] eq 'Module: Test; Score: -5; Helo hostname is unknown'
        && scalar @details == 4, "Helo is invalid"
    );
}


# setup test datbase
TEST_FQDN_OTHER: {
    
    my $attrs_ref = {
        %attrs,
        recipient => 'bla@asd',
        sender    => 'blub@???'
    };
    session_init( $server, $attrs_ref );
    
    $server->session->spam_score( 0 );
    eval {
        $module->handle();
    };
    my @details = @{ $server->session->spam_details };
    #print "HERE ". Dumper( [ $server->session->spam_score, @details ] );
    ok( $server->session->spam_score == -20
        && $details[0] eq 'Module: Test; Score: -5; Recipient address is not in FQDN'
        && $details[1] eq 'Module: Test; Score: -5; Sender address is not in FQDN'
        && $details[2] eq 'Module: Test; Score: -5; Recipient domain is unknown'
        && $details[3] eq 'Module: Test; Score: -5; Sender domain is unknown',
        "Sender and recipient address not FQDN"
    );
}


# setup test datbase
TEST_UNKNOWN_OTHER: {
    
    my $attrs_ref = {
        %attrs,
        sender    => 'asd@sender-'. time(). '.tld',
        recipient => 'asd@recipient-'. time(). '.tld'
    };
    session_init( $server, $attrs_ref );
    
    $server->session->spam_score( 0 );
    eval {
        $module->handle();
    };
    my @details = @{ $server->session->spam_details };
    #print "HERE ". Dumper( [ $server->session->spam_score, @details ] );
    ok( $server->session->spam_score == -10
        && $details[0] eq 'Module: Test; Score: -5; Recipient domain is unknown'
        && $details[1] eq 'Module: Test; Score: -5; Sender domain is unknown'
        && scalar @details == 3, "Sender and recipient domains unknown"
    );
}







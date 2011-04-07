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


my $module = init_module( $server, 'DummyContentFilterWHITELIST' );


session_init( $server );
$server->session->set_flag( 'whitelisted' );

eval {
    my $res = $module->handle();
};
$@ && diag( "Exception: ". ref($@). " ($@)" );

ok(
    ! $@ && scalar @{ $server->session->spam_details } == 1,
    "Filter result found"
);

ok(
    $server->session->spam_details->[0] =~ /Skipped due to whitelisting/,
    "Whitelisting correct"
);



#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


plan skip_all => "Geo::IP not installed, skipping tests"
    unless eval "use Geo::IP; 1;";

my $server = init_server( 'Doorman' );
plan tests => 6;



my $module = init_module( $server, GeoWeight => {} );

my %ips = (
    'fr' => '213.41.120.195', # elysee.fr
    'de' => '217.79.215.140', # bundestag.de
    'us' => '72.14.221.99',   # google.com
);

# setup test datbase
TEST_DE: {
    
    # build data for test
    my $attrs_ref = {
        client_address  => $ips{ de }
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle( undef, $attrs_ref );
    };
    ok( ! $@ && $weight_before + 20 == $server->session->spam_score, "DE recognized" );
}


TEST_US: {
    
    # build data for test
    my $attrs_ref = {
        client_address  => $ips{ us }
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle( undef, $attrs_ref );
    };
    ok( ! $@ && $weight_before + 10 == $server->session->spam_score, "US recognized" );
}


TEST_FR: {
    
    # build data for test
    my $attrs_ref = {
        client_address  => $ips{ fr }
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle( undef, $attrs_ref );
    };
    ok( ! $@ && $weight_before - 10 == $server->session->spam_score, "FR recognized" );
}


TEST_LOCAL: {
    
    # build data for test
    my $attrs_ref = {
        client_address  => '127.0.0.1'
    };
    session_init( $server, $attrs_ref );
    
    my $weight_before = $server->session->spam_score;
    eval {
        $module->handle( undef, $attrs_ref );
    };
    ok( ! $@ && $weight_before == $server->session->spam_score, "Other recognized" );
}




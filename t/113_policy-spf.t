#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Policy' );
    use Test::More tests => 4;
}

skip "Mail::SPF not installed, skipping tests", 4
    unless eval "use Mail::SPF; 1;";

my $module = init_module( $server, SPF => {} );


# get us a test ip
my $valid_ip;
RETREIVE_IP: {
    eval {
        my $dns = Net::DNS::Resolver->new;
        my $res = $dns->query( "gmx.com", "TXT" );
        ( $valid_ip ) =
            map {
                chomp;
                my ( $ip ) = $_ =~ /ip4:(\d+\.\d+\.\d+\.\d+)/;
                $ip;
            }
            map {
                $_->rdatastr 
            } $res->answer
        ;
    };
    ok( !$@ && $valid_ip, "Retreive Test IP from gmx.." ) or die( "Problem: $@" );;
};



# build data for test
my $attrs_ref = {
    client_address => '192.168.0.255',
    sender         => 'someone-'. time(). '@gmx.com'
};

# test negative
CHECK_NEGATIVE: {
    session_init( $server, $attrs_ref );
    eval {
        $module->handle();
    };
    ok_for_reject( $server, $@, "Hit for invalid IP" );
}

# test positive
CHECK_POSTIVE: {
    $attrs_ref->{ client_address } = $valid_ip;
    session_init( $server, $attrs_ref );
    eval {
        $module->handle();
    };
    ok_for_dunno( $server, $@, "Pass for valid IP" );
}





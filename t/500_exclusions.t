#!/usr/bin/perl

use strict;
use Test::More;
use Mail::Decency::Helper::Cache;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use Data::Dumper;
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Policy', {
        exclusions => {
            database => 1,
            modules  => {
                Honeypot => {
                    from_domain => [ 'senderdont.tld' ],
                    to_domain   => [ 'recipientdont.tld' ]
                },
            },
            file => 'exclusions.txt',
            dir  => "$Bin/sample/exclusions"
        }
    }, { init_database => 1 } );
    use Test::More tests => 8;
}



init_database( $server );
my $module = init_module( $server, Honeypot => {} => {
    name => 'Honeypot'
}  );


# create records
CREATE_RECORDS: {
    eval {
        $server->database->set( exclusions => policy => {
            type   => 'from_domain',
            module => 'honeypot',
            value  => 'ignoreme.tld'
        } );
    };
    ok( !$@, "Database records created" ) or diag( "Problem: $@" );
}

my %attrs_default = (
    client_address => '192.168.1.2',
    recipient      => 'lalala@spamlover.tld',
);

# check wheter not associated sender passes
CHECK_HONEYPOT: {
    my %attrs = (
        %attrs_default,
        sender => 'blaa@sender.tld',
    );
    session_init( $server, \%attrs );
    my ( undef, undef, $err ) = $server->handle_child( $module );
    ok_for_reject( $server, $err, "Reject for listed recipient address" );
}

# check wheter not associated sender passes
CHECK_CONFIG: {
    my %attrs = (
        %attrs_default,
        sender => 'blaa@senderdont.tld',
    );
    session_init( $server, \%attrs );
    my ( undef, undef, $err ) = $server->handle_child( $module );
    ok_for_dunno( $server, $err, "Exclude via config" );
}

# check wheter not associated sender passes
CHECK_DATABASE: {
    my %attrs = (
        %attrs_default,
        sender => 'blaa@ignoreme.tld',
    );
    session_init( $server, \%attrs );
    my ( undef, undef, $err ) = $server->handle_child( $module );
    ok_for_dunno( $server, $err, "Exclude via database" );
}

# check wheter not associated sender passes
CHECK_DIR: {
    my %attrs = (
        %attrs_default,
        sender => 'blaa@thisdomain.tld',
    );
    session_init( $server, \%attrs );
    my ( undef, undef, $err ) = $server->handle_child( $module );
    ok_for_dunno( $server, $err, "Exclude via dir" );
}

# check wheter not associated sender passes
CHECK_FILE: {
    my %attrs = (
        %attrs_default,
        sender => 'blaa@fromfile.tld',
    );
    session_init( $server, \%attrs );
    my ( undef, undef, $err ) = $server->handle_child( $module );
    ok_for_dunno( $server, $err, "Exclude via file" );
}



cleanup_server( $server );




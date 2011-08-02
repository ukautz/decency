#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use MIME::QuotedPrint;
use Data::Dumper;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;

my ( $server );
BEGIN { 
    $server = init_server( 'Detective' );
    use Test::More tests => 9;
}


SKIP: {
    
    chomp( my $bash = `which bash` );
    skip "Sorry, need bash in /bin/bash for this test", 4
        if ! $bash || ! -x $bash || $bash ne '/bin/bash';

    # init session from written mime file
    session_init( $server );
    
    # init moduole
    my $module = init_module( $server, 'DummyDetectiveCMDTEST', {
        timeout   => 1,
        cmd_check => "$Bin/sample/cmd-test.sh"
    } );
    #push @{ $server->childs }, $module;
    
    my $start = time();
    my ( $handled, $state, $error );
    eval {
        #print Dumper( $server_module->session );
        ( $handled, $state, $error ) = $server->handle_child( $module );
    };
    ok( ! $@ && ! ref( $@ ), "Child handle without external error" );
    my $end = time();
    ok( $handled, "Module handled" );
    ok( $state eq 'ongoing', "Mail still in modules queue" );
    ok( $error && ref( $error ) && ref( $error ) eq 'Mail::Decency::Core::Exception::Timeout',
        'Timeout exception thrown' );
    ok( $end - $start <= 2, 'Timeout thrown in time' ); 
};


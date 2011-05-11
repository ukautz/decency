#!/usr/bin/perl

use strict;
use Test::More;
use File::Temp qw/ tempfile /;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'Detective' );
    use Test::More tests => 4;
}

SKIP: {

    skip "ClamAV::Client not installed, skipping tests", 4 unless eval "use ClamAV::Client; 1;";
    ok( eval "use Mail::Decency::Detective::ClamAV; 1;", "Mail::Decency::Detective::ClamAV Loaded" )
        or die "could not load: Mail::Decency::Detective::ClamAV";
    
    skip "Require LWP::UserAgent to get EICAR (dummy virus)", 3
        unless eval "use LWP::UserAgent; 1;";
    
    skip "ClamAV test, enable with USE_CLAMAV=1 and set optional CLAMAV_PATH for the tests (default: /var/run/clamav/clamd.ctl)", 3
        unless $ENV{ USE_CLAMAV };
    
    my $module = init_module( $server, ClamAV => {
        path => $ENV{ CLAMAV_PATH } || '/var/run/clamav/clamd.ctl'
    } );
    session_init( $server );
    
    
    my ( $th, $eicar_file ) = tempfile( "$Bin/data/eicar-XXXXXX", UNLINK => 0 );
    GET_EICAR: {
        
        my $lwp = LWP::UserAgent->new;
        my $req = HTTP::Request->new( GET => 'http://www.eicar.org/download/eicar.com.txt' );
        my $res = $lwp->request( $req );
        
        if ( $res->is_success ) {
            print $th $res->decoded_content;
            ok( 1, "Download EICAR" );
            close $th;
        }
        else {
            ok( 0, "Download EICAR" );
            unlink( $eicar_file );
            die "No EICAR, no test\n";
        }
    }
    
    
    FILTER_TEST: {
        
        # add eicar
        $server->session->mime->attach(
            Path     => $eicar_file,
            Type     => "application/octet-stream",
            Encoding => "base64"
        );
        $server->session->write_mime;
        
        eval {
            my $res = $module->handle();
        };
        
        ok(
            $@
            && $server->session->virus
            && $server->session->virus =~ /Eicar-Test-Signature/,
            "ClamAV found virus"
        );
    }
    
    unlink( $eicar_file );
}


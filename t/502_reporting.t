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
my $reporting_file;
BEGIN { 
    $reporting_file = "$Bin/data/reporting.log";
    use Test::More tests => 3;
}

my @tests = (
    [ DummyPolicyOK => 'Module: DummyPolicyOK; Score: 0; All good, all the time' => 'ok', qr/^OK$/ ],
    [ DummyPolicyDUNNO => 'Module: DummyPolicyDUNNO; Score: 0; I dont know' => 'ongoing', qr/^PREPEND / ],
    [ DummyPolicyREJECT => 'Module: DummyPolicyREJECT; Score: 0; Dont like it, dont want it' => 'spam', qr/^REJECT / ]
);

my $locker = get_semaphore();

foreach my $test_ref( @tests ) {
    subtest $test_ref->[0] => sub {
        plan tests => 9;
        test_answer( @$test_ref );
    };
}


sub test_answer {
    my ( $module_name, $report_info, $report_state, $action_rx ) = @_;
    
    my $server = init_server( 'Policy', {
        reporting => {
            file => $reporting_file
        },
    } );
    
    my $attrs_ref = {
        client_address => '1.1.1.1',
        sender         => "from\@sender.tld",
        recipient      => "to\@recipient.tld",
    };
    
    my $module = init_module( $server, $module_name )
        or BAIL_OUT( "Require module $module_name" );
    push @{ $server->childs }, $module;
    my $time_before = time();
    
    my $handler = $server->get_handlers();
    
    my $res;
    eval {
        $res = $handler->( $server, $attrs_ref );
    };
    ok( !$@ && $res && ref( $res ) eq 'HASH', "Server handled" )
        or BAIL_OUT( "Cannot continue without server response" );
    ok( $res->{ action } =~ $action_rx, "Response is OK" )
        or BAIL_OUT( "Cannot continue without correct server response, got $res->{ action }, want $action_rx" );
    
    if ( -f $reporting_file ) {
        open my $fh, '<', $reporting_file
            or BAIL_OUT( "Error openening report file '$reporting_file': $!" );
        my ( $line ) = <$fh>;
        close $fh;
        chomp $line;
        my ( $time, $id, $server_prefix, $from, $to, $size, $state, $message )
            = split( /\t+/, $line );
        ok( $time >= $time_before && $time <= time(), "Report time OK" );
        ok( $from eq 'from@sender.tld', "Report sender OK ($from)" );
        ok( $to eq 'to@recipient.tld', "Report recipient OK" );
        ok( $size == 0, "Report size OK" );
        ok( $state eq $report_state, "Report state" )
            or fail( "Got state '$state', expexted '$report_state'" );
        ok( $message eq $report_info, "Report spam info OK" )
            or fail( "Got info '$message', expexted '$report_info'" );
    }
    else {
        fail( "Reporting file has not been created" );
    }
    
    undef $module;
    undef $server;
    
    unlink( $reporting_file ) if -f $reporting_file;
}


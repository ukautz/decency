#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;
use Data::Dumper;


my $server;
BEGIN { 
    $server = init_server( 'Detective' );
    use Test::More tests => 9;
}

my $archive_base = "$Bin/data/spool-dir/archive";
my $module = init_module( $server, Archive => {
    archive_dir => "$archive_base/\%recipient_domain\%/\%recipient_prefix\%"
} );

SETUP_DATABASE: {
    init_database( $server );
    ok( 1, "Setup database" );
}

FILTER_TEST: {
    session_init( $server );
    eval {
        my $res = $module->handle();
    };
    
    # check disk
    my $files_ref = get_archive_files();
    ok(
        defined $files_ref->{ 'other-domain.tld' }
        && defined $files_ref->{ 'other-domain.tld' }->{ 'recipient' },
        "Mail archiving"
    );
    
    # check database
    my $db = $module->database;
    my $indexed_ref = $db->get( archive => index => {
        from_domain => $server->session->from_domain,
        from_prefix => $server->session->from_prefix,
    } );
    ok(
        $indexed_ref->{ search } eq 'hello mail mime this yadda',
        "Full text index"
    );
    ok(
        $indexed_ref->{ subject } eq 'This is the Subject',
        "Mail Subject"
    );
    ok(
        $indexed_ref->{ to_domain } eq 'other-domain.tld'
        && $indexed_ref->{ to_prefix } eq 'recipient',
        "Mail To"
    );
}

FILTER_HTML_MAIL: {
    session_init( $server, "$Bin/sample/eml/htmlmail.eml" );
    eval {
        my $res = $module->handle();
    };
    
    # check disk
    my $files_ref = get_archive_files();
    ok(
        defined $files_ref->{ 'recipient.tld' }
        && defined $files_ref->{ 'recipient.tld' }->{ 'me' },
        "Mail archiving 2"
    );
    
    # check database
    my $db = $module->database;
    my $indexed_ref = $db->get( archive => index => {
        from_domain => 'sender.tld',
        from_prefix => 'bla',
    } );
    ok(
        $indexed_ref->{ search } eq 'are bla how html mail things this yadda',
        "Full text index from HTML"
    );
}


sub get_archive_files {
    my $path = shift || $archive_base;
    my $res  = shift || {};
    my @files = glob( "$path/*" );
    foreach my $file( @files ) {
        if ( -d $file ) {
            get_archive_files( $file, $res );
        }
        else {
            $file =~ s#^\Q$archive_base\E/##;
            if ( $file =~ /^(.+?)\/(.+?)\-(.+?)$/ ) {
                my ( $domain, $prefix, $unique ) = ( $1, $2, $3 );
                $res->{ $domain } ||= {};
                $res->{ $domain }->{ $prefix } ||= {};
                $res->{ $domain }->{ $prefix }->{ $unique } = 1; 
            }
        }
    }
    return $res;
}

#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use MIME::QuotedPrint;
use Data::Dumper;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;

my ( $doorman, $detective );
BEGIN { 
    $doorman   = init_server( 'Doorman' );
    $detective = init_server( 'Detective' );
    use Test::More tests => 9;
}

my $doorman_module = init_module( $doorman, 'DummyDoormanCOMMUNICATE' );
my $detective_module = init_module( $detective, 'DummyDetectiveCOMMUNICATE' );

# those simulate postfix attributes
my $attrs_ref = {
    client_address => '255.255.0.0',
    sender         => 'doesnt@matter.tld',
    recipient      => 'recipient@domain.tld'
};

session_init( $doorman, $attrs_ref );
eval {
    $doorman_module->handle();
};
ok_for_dunno( $doorman, $@, "Handle in Doorman" );

# get result from doorman
my $doorman_result = $doorman->session_cleanup();
my ( $doorman_result_header, $doorman_result_content ) =
    $doorman_result =~ /^prepend (.+?): (.+?)$/i;


#
# CORRECT HEADER
#

my $mime_file = mime_file( $doorman_result_header, $doorman_result_content );

# init session from written mime file
session_init( $detective, $mime_file );

eval {
    #print Dumper( $detective_module->session );
    $detective_module->handle();
};

ok(
    $detective->session->spam_details->[0] eq 'Module: DummyDoormanCOMMUNICATE; Score: 33; Got Score from Doorman',
    "Valid Header: Module message from Doorman in Detective"
);
ok(
    $detective->session->spam_details->[1] eq 'Module: DummyDetectiveCOMMUNICATE; Score: 100; Got Flag from Doorman',
    "Valid Header: Flag set from Doorman found in Detective"
);


#
# WRONG HEADER
#

my @doorman_result_content = split( /\|/, $doorman_result_content );

# corrupt signature
$doorman_result_content[1] = substr( $doorman_result_content[1], 0, -5 ) . '12345';
my $doorman_result_content_fail = join( '|', @doorman_result_content );

my $mime_file = mime_file( $doorman_result_header, $doorman_result_content_fail );

# init session from written mime file
session_init( $detective, $mime_file );

eval {
    #print Dumper( $detective_module->session );
    $detective_module->handle();
};

ok(
    scalar( @{ $detective->session->spam_details } ) == 1
    && $detective->session->spam_details->[0] eq 'Module: DummyDetectiveCOMMUNICATE; Score: -100; Missing Flag from Doorman',
    "Corrupt Header: No SPAM details and no flag from Doorman"
);



#
# TRANSPORT VIA CACHE
#

# those simulate postfix attributes
$attrs_ref = {
    client_address => '255.255.0.0',
    sender         => 'doesnt@matter.tld',
    recipient      => 'recipient@domain.tld',
    instance       => '645A21A258'
};
session_init( $doorman, $attrs_ref );
eval {
    $doorman_module->handle();
};
ok_for_dunno( $doorman, $@, "Handle with instance id in Doorman" );

# cleanup writes cache
$doorman_result = $doorman->session_cleanup();

# use the FAILed header .. which will be ignored, cause the cache is used
my $mime_file = mime_file( $doorman_result_header, $doorman_result_content );

# init session from written mime file
session_init( $detective, $mime_file );

eval {
    $detective_module->handle();
};

ok(
    $detective->session->spam_details->[0] eq 'Module: DummyDoormanCOMMUNICATE; Score: 33; Got Score from Doorman',
    "From Cache: Module message from Doorman in Detective"
);
ok(
    $detective->session->spam_details->[1] eq 'Module: DummyDetectiveCOMMUNICATE; Score: 100; Got Flag from Doorman',
    "From Cache: Flag set from Doorman found in Detective"
);




sub mime_file {
    my ( $header, $content ) = @_;
    my $mime_out = "$Bin/data/spool-dir/communicate.eml";
    
    # open MIME file
    my $parser = MIME::Parser->new;
    mkdir( "$Bin/data/spool-dir/communicate" ) unless -d "$Bin/data/spool-dir/communicate";
    die "Could not make testing directory '$Bin/data/spool-dir/communicate'"
        unless -d "$Bin/data/spool-dir/communicate";
    $parser->output_under( "$Bin/data/spool-dir/communicate" );
    my $mime = $parser->parse_open( "$Bin/sample/eml/testmail.eml" );
    
    # write header from Doormanm
    $mime->head->set( $header => $content );
    
    # write mime file to output
    open my $temp, '>', $mime_out
        or die "Cannot open '$mime_out' for write: $!";
    $mime->print( $temp );
    close $temp;
    undef $mime;
    undef $parser;
    
    return $mime_out;
}

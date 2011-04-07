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
    use Test::More tests => 4;
}

my $module = init_module( $server, MimeAttribs => {} );


eval {
    session_init( $server );
    $module->handle();
};
ok_mime_header( $module, 'X-Something', sub {
    my $ref = shift;
    return 0 if $#$ref != 0;
    chomp $ref->[0];
    return $ref->[0] eq 'Something is there';
}, "Add header X-Something" );

ok_mime_header( $module, 'Subject', sub {
    my $ref = shift;
    return 0 if $#$ref != 0;
    chomp $ref->[0];
    return $ref->[0] eq 'PREFIX: This is the Subject';
}, "Replace content in Subject" );

ok_mime_header( $module, 'X-Universally-Unique-Identifier', sub {
    my $ref = shift;
    return 1 if $#$ref != 0;
    return 0;
}, "Remove X-Universally-Unique-Identifier" );








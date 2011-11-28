#!/usr/bin/perl

use Test::More tests => 36;

#
# VERSION 0.1.6
#

BEGIN {
    ok( eval "use v5.10; 1", "Perl 5.10" ) or die "Perl 5.10 required";
    
    my @required = qw(
        Archive::Tar    1.40
        Crypt::OpenSSL::RSA    0
        Data::Pager    0
        DateTime    0
        Digest::MD5    0
        Digest::SHA    0
        Email::Valid    0
        File::Path    2.07
        File::Temp    0
        IO::String    0
        IO::YAML    0.08
        Mail::Field::Received   0
        MIME::Lite    0
        MIME::Parser    0
        MIME::QuotedPrint    0
        Mouse    0
        MouseX::NativeTraits    0
        Net::DNS::Resolver    0
        Net::LMTP    0
        Net::Server::PreFork
        Net::SMTP    0
        Proc::ProcessTable    0
        Regexp::Common    0
        Regexp::IPv6    0
        Storable    0
        Time::HiRes    0
        YAML    0
        Cache::File    0
        DBD::SQLite    0
        DBI    0
        DBIx::Connector    0
        SQL::Abstract::Limit    0
        Module::Build      0.2805
        Test::More         0
    );
    
    while( @required ) {
        my $m = shift @required; my $v = shift @required;
        ( $v ? use_ok( $m, $v ) : use_ok( $m ) )
            or BAIL_OUT( sprintf( 'Require module %s%s', $m, $v ? " v$v" : '' ) );
    }
};

#
# Module::Build build script for Mail::SPF
#
# (C) 2005-2008 Julian Mehnle <julian@mehnle.net>
# $Id: Build.PL 50 2008-08-17 21:28:15Z Julian Mehnle $
#
##############################################################################

use Module::Build 0.26;
use version;

my $build = Module::Build->new(
    module_name => 'Mail::Decency',
    dist_author => [
        'Ulrich Kautz <uk@fortrabbit.de>',
    ],
    license => 'perl',
    requires => {
        Archive::Tar => '1.40',
        Carp => 0,
        Crypt::OpenSSL::RSA => 0,
        Data::Pager => 0,
        DateTime => 0,
        Digest::MD5 => 0,
        Digest::SHA => 0,
        Email::Valid => 0,
        File::Basename => 0,
        File::Copy => 0,
        File::Path => '2.07',
        File::Temp => 0,
        IO => '1.24',
        IO::String => 0,
        IO::YAML => 0.08,
        MIME::Lite => 0,
        MIME::Parser => 0,
        MIME::QuotedPrint => 0,
        Mail::Field::Received => 0,
        Mouse => 0,
        MouseX::NativeTraits => 0,
        Net::DNS::Resolver => 0,
        Net::Domain::TLD => 0,
        Net::LMTP => 0,
        Net::Netmask => 0,
        Net::SMTP => 0,
        POE => 0,
        POE::Filter::Postfix => 0,
        Proc::ProcessTable => 0,
        Regexp::Common => 0,
        Regexp::IPv6 => 0,
        Scalar::Util => 0,
        Storable => 0,
        Sys::Syslog => 0,
        Time::HiRes => 0,
        YAML => 0,
    },
    recommends => {
        NetAddr::IP     => '4.007'  # has all $& and $` removed for better performance
    },
    build_requires => {
        Cache::File => 0,
        DBD::SQLite => 0,
        DBI => 0,
        DBIx::Connector => 0,
        SQL::Abstract::Limit => 0,
        Module::Build   => '0.2805',
        Test::More      => 0,
        
        # optional, for modules which can be tested
        Mail::SPF => 0,
        Mail::DKIM => 0,
        Net::DNSBL::Client => 0
    },
    optional => {
        MongoDB => 0.35,
        Net::LDAP => 0,
        ClamAV::Client => 0,
        Cache::FastMmap => 0,
        Cache::Memcache => 0,
        Cache::Memcache::XS => 0,
        
        # should not be installed via perl .. rather then by distri installer
        #Mail::SpamAssassin => 0,
    },
    sign => 1
);

$build->add_build_element($_)
    foreach qw(sbin);

$build->create_build_script();

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
    $server = init_server( 'Policy', {
        stats => {
            
                # module_results
                # module_performance
            enable => [ qw/
                final_state
            / ],
            intervals => [ qw/
                hour
                day
                week
                month
                year
            / ],
            maintenance => {
                stream => '50d',
                intervals => {
                    hour => 336,
                    day => 60,
                    week => 52,
                    month => 24,
                    year => 10
                }
            }
        }
    }, {
        no_db_setup => 1
    } );
    use Test::More tests => 6;
}



my $module1 = init_module( $server, 'DummyPolicyDUNNO' );
my $module2 = init_module( $server, 'DummyPolicyOK' );

init_database( $server );
#print "CHECK ". $server->check_database( $server->schema_definition ). "\n";;

my $attrs_ref = {
    client_address => '1.1.1.1',
    sender         => "from\@sender.tld",
    recipient      => "to\@recipient.tld",
};
push @{ $server->childs }, $module1;
push @{ $server->childs }, $module2;
my $handler = $server->get_handlers();
eval {
    $handler->( $server, $attrs_ref );
};

# my @r1 = $server->database->search( stats => 'policy_performance' );
# my @r2 = $server->database->search( stats => 'policy_results' );
# print Dumper( { R1 => \@r1, R2 => \@r2 } );

my @r3 = $server->database->search( stats => 'policy_finalstate' );
print Dumper( { R3 => \@r3 } );


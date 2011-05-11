#!/usr/bin/perl


use strict;
use warnings;
use FindBin qw/ $Bin /;

BEGIN {
    
    # check all available dirs
    foreach my $dir( (
        '/opt/decency/lib',
        '/opt/decency/locallib',
        '/opt/decency/locallib/lib/perl5',
        "$Bin/../lib"
    ) ) {
        -d $dir && eval 'use lib "'. $dir. '"';
    }
    
    # try load local lib also
    eval 'use local::lib';
}

use Data::Dumper;
use YAML;
use Getopt::Long;
use Mail::Decency::Core::Stats;
use Mail::Decency::Helper::Database;
use DateTime;

my %opt;
GetOptions(
    "config|c=s" => \( $opt{ config } = "" ),
    "data|d=s"   => \( $opt{ data } = "" ),
    "module|m=s"   => \( $opt{ module } = "" ),
    "period|p=s" => \( $opt{ period } = "" ),
    "class|a=s"  => \( $opt{ class } = "" ),
);
die "Require --config, provide any server config with database settings\n"
    unless $opt{ config };
die "Config file '$opt{ config }' does not exits or not readable\n"
    unless -f $opt{ config };

my $config = YAML::LoadFile( $opt{ config } );
die "Configuration file does not contain databse configuration\n"
    unless $config->{ database };

$opt{ class } =~ s/[-_]//;

our %TIME_FORMAT = (
    hour    => '%H %F',
    day     => '%F',
    week    => '%W %Y',
    month   => '%m-%Y',
    year    => '%Y',
);

my $db = get_db();



if ( $opt{ data } =~ /^final[-_]state$/ ) {
    
    my %search = ();
    $search{ module } = $opt{ module } if $opt{ module };
    $search{ period } = $opt{ period } if $opt{ period };
    
    print "READ $opt{ class }\n";
    my @search = ( stats => $opt{ class }. '_finalstate' => \%search );
    my ( $read, $handle ) = $db->search_read( @search );
    my $count = $db->count( @search);
    print Dumper( [ $count ] );
    my %periods = ();
    while ( my $item = $read->$handle ) {
        my $p_ref = $periods{ $item->{ period } } ||= {};
        my $period = DateTime->from_epoch( epoch => $item->{ start } )
            ->strftime( $TIME_FORMAT{ $item->{ period } } );
        my $pp_ref = $p_ref->{ $period } ||= {};
        $pp_ref->{ $item->{ state } } += $item->{ amount };
    }
    print Dumper( \%periods );
}

elsif ( $opt{ data } =~ /^module[-_]performance$/ ) {
    
    my %search = ();
    $search{ module } = $opt{ module } if $opt{ module };
    $search{ period } = $opt{ period } if $opt{ period };
    
    print "READ $opt{ class }\n";
    my @search = ( stats => $opt{ class }. '_performance' => \%search );
    my ( $read, $handle ) = $db->search_read( @search );
    my $count = $db->count( @search);
    print Dumper( [ $count ] );
    my %periods = ();
    while ( my $item = $read->$handle ) {
        my $p_ref = $periods{ $item->{ period } } ||= {};
        my $period = DateTime->from_epoch( epoch => $item->{ start } )
            ->strftime( $TIME_FORMAT{ $item->{ period } } );
        my $pp_ref = $p_ref->{ $period } ||= {};
        $item->{ module } =~ s/^.*://;
        $item->{ module } =~ s/=.*$//;
        my $ppp_ref = $pp_ref->{ $item->{ module } } ||= { calls => 0, runtime => 0 };
        $ppp_ref->{ calls } += $item->{ calls };
        $ppp_ref->{ runtime } += $item->{ runtime };
        
    }
    
    foreach my $period( qw/ hour day week month year / ) {
        next unless $periods{ $period };
        foreach my $time( sort keys %{ $periods{ $period } } ) {
            my $period_ref = $periods{ $period }->{ $time };
            foreach my $module( sort keys %$period_ref ) {
                print "$period;$time;$module;$period_ref->{ $module }->{ calls };$period_ref->{ $module }->{ runtime }\n";
            }
        }
    }
    #print Dumper( $periods{ month } );
}


sub get_db {
    my $type = $config->{ database }->{ type }
        or die "Missing type for database!\n";
    return Mail::Decency::Helper::Database->create( $type => $config->{ database } );
}





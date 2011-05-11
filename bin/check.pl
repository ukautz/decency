#!/usr/bin/perl


=head1 NAME

check.pl - Check script for decency servers

=head1 DESCRIPTION

Check wheter decency server is running

Exists with 1 if not running, 2 if no or not enough child instances are running and 0 if everything is good.

=head1 SYNOPSIS

    check.pl --class doorman --config /etc/decency/doorman.yml

=head1 METHODS

=cut


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

use version 0.74; our $VERSION = qv( "v0.2.0" );

use YAML;
use Getopt::Long;
use Mail::Decency::Helper::Shell qw/
    switch_user_group
    pid_is_running
    get_child_pids
    pid_from_file
/;
use Mail::Decency::Helper::Config qw/
    merged_config
/;


my %opt;
GetOptions(
    "class|a=s"  => \( $opt{ class } = "" ),
    "config|c=s" => \( $opt{ config } = "" ),
    "pid|p=s"    => \( $opt{ pid } = "" ),
);

die "Provide --class <doorman|detective|log-parser>\n"
    unless $opt{ class } && $opt{ class } =~ /^(?:doorman|detective|log\-parser)$/;

# if config default, replace variable with class
$opt{ config } = sprintf( $opt{ config }, $opt{ class } )
    if $opt{ config } =~ /\%s/;
$opt{ config} ||= "/etc/decency/$opt{ class }.yml";
$opt{ pid } ||= "/tmp/$opt{ class }.pid";


# get master pid
my $master_pid = pid_from_file( $opt{ pid } );
die "Could not retreive pid from $opt{ pid }\n"
    unless $master_pid;

# master not running:
exit 1
    unless pid_is_running( $master_pid );

# get childs
my @child_pids = get_child_pids( $master_pid );

# no childs
exit 2
    if scalar( @child_pids ) == 0;

# get config
my $config = merged_config( \%opt );

# determine required amount of instances
my $required_instances = $config->{ server }->{ instances } || 0;
exit 2
    unless scalar( @child_pids ) == $required_instances;

# all good, all the time
exit 0;

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


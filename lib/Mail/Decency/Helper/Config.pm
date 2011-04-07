package Mail::Decency::Helper::Config;

=head1 NAME

Mail::Decency::Helper::Config

=head1 DESCRIPTION


=cut

use strict;
use warnings;
use base qw/ Exporter /;
use YAML;

our @EXPORT = qw/
    merged_config
/;


=head1 METHODS

=head2 switch_user_group

Switches to given user and / or group

    my ( $username, $groupname )
        = switch_user_group( $user_or_uid, $group_or_gid );

=cut

sub merged_config {
    my ( $opt_ref ) = @_;
    
    my $config = YAML::LoadFile( $opt_ref->{ config } );
    
    # update log level
    $config->{ logging } ||= { syslog => 1, console => 0, directory => undef };
    $config->{ logging }->{ log_level } = $opt_ref->{ log_level };
    $config->{ logging }->{ console }   = ! $opt_ref->{ daemon };
    
    # read instances from config
    $config->{ server }->{ instances } = 3
        unless defined $config->{ server }
        && defined $config->{ server }->{ instances }
        && $config->{ server }->{ instances } > 0
    ;
    
    # having other port to bind on ?
    $config->{ server }->{ port } = $opt_ref->{ port }
        if $opt_ref->{ port };
    
    # having other hostname / ip to bind on ?
    $config->{ server }->{ host } = $opt_ref->{ host }
        if $opt_ref->{ host };
    
    return $config;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

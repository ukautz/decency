package Mail::Decency::Helper::Shell;

=head1 NAME

Mail::Decency::Helper::Shell

=head1 DESCRIPTION

Helper methods for the shell scripts (decency.pl, decency-webserver.pl)

=cut

use strict;
use warnings;

use Proc::ProcessTable;

use base qw/ Exporter /;

our @EXPORT = qw/
    switch_user_group
    pid_is_running
    get_child_pids
    pid_from_file
/;


=head1 METHODS

=head2 switch_user_group

Switches to given user and / or group

    my ( $username, $groupname )
        = switch_user_group( $user_or_uid, $group_or_gid );

=cut

sub switch_user_group {
    my ( $user_or_uid, $group_or_gid ) = @_;
    
    # having user arg ? become someone else ..
    if ( $user_or_uid ) {
        my $uid = $user_or_uid =~ /^\d+$/
            ? $user_or_uid
            : getpwnam( $user_or_uid )
        ;
        DD::cop_it "Cannot determine UID for \"$user_or_uid\"\n"
            unless defined $uid;
        $> = $uid;
    }
    $user_or_uid = getpwuid( $> );
    
    # having group arg ? become someone else ..
    if ( $group_or_gid ) {
        my $gid = $group_or_gid =~ /^\d+$/
            ? $group_or_gid
            : getgrnam( $group_or_gid )
        ;
        DD::cop_it "Cannot determine GID for \"$group_or_gid\"\n"
            unless defined $gid;
        $) = $gid;
    }
    $group_or_gid = getgrgid( $) );
    
    return ( $user_or_uid, $group_or_gid );
}


=head2 pid_from_file

Get's pid from pidfile

=cut

sub pid_from_file {
    my ( $file ) = @_;
    return unless -f $file;
    open my $fh, '<', $file
        or DD::cop_it "Could not open '$file' for read: $!";
    my ( $pid ) = <$fh>;
    close $fh;
    chomp $pid;
    return $pid if $pid =~ /^[0-9]+$/;
    return;
}


=head2 pid_is_running

Checks via "kill 0" and Proc::ProcessTable wheter a pid is still up and not defunct

    if ( pid_is_running( $pid ) ) {
        # ..
    }

=cut

sub pid_is_running {
    my $p = shift;
    
    # the easy wway ..
    return 0
        unless kill 0, $p;
    
    # the hard way
    my $ps = Proc::ProcessTable->new;
    return scalar( grep { $_->state ne 'defunct' && $_->pid == $p } @{ $ps->table } ) > 0;
}


=head2 get_child_pids

Returns all child pids of a running process

=cut

sub get_child_pids {
    my $p = shift;
    my $ps = Proc::ProcessTable->new;
    return map { $_->pid } grep { $_->ppid == $p } @{ $ps->table };
}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

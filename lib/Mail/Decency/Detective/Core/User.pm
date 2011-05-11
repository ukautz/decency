package Mail::Decency::Detective::Core::User;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;

=head1 NAME

Mail::Decency::Detective::Core::User

=head1 DESCRIPTION

Extensions for modules requiring a user (eg command line tools ..)

=head1 CLASS ATTRIBUTES

=head2 cmd_user : Str

Command for tretreiving a user for the command line variable "%user%" 

=cut

has cmd_user => ( is => 'rw', isa => 'Str', predicate => 'has_cmd_user' );

=head2 default_user : Str

User which will be used if none could be determined (if not set, the via "to" provided recipient will be used) 

=cut

has default_user => ( is => 'rw', isa => 'Str', predicate => 'has_default_user' );



=head1 METHOD MODIFIERS

=head2 before pre_init

Add check params: cmd, check, train and untrain to list of check params

=cut

before pre_init => sub {
    shift->add_config_params( qw/ cmd_user default_user / );
};


=head1 METHODS

=head2 get_user

Determines the user for the command line script .. eg "dspam --user %user%"

=cut

sub get_user {
    my ( $self ) = @_;
    
    # getting hit from cache ?
    my $cache_name = $self->name. "-User-". $self->to;
    # my $cached = $self->cache->get( $cache_name );
    # return $cached if $cached;
    
    my $user;
    
    # using command to retreive home
    if ( $self->has_cmd_user ) {
        $user = $self->get_user_by_cmd;
        $self->logger->debug3( "Got user '$user' from cmd" ) if $user;
    }
    
    # having module fallback method ?
    elsif ( $self->can( 'get_user_fallback' ) ) {
        $user = $self->get_user_fallback;
        $self->logger->debug3( "Got user '$user' from fallback" ) if $user;
    }
    
    # determine fallback user
    $user ||= $self->has_default_user
        ? $self->default_user
        : $self->to
    ;
    $self->logger->debug3( "Got final user '$user'" );
    
    # write to cache
    $self->cache->set( $cache_name => $user );
    
    
    
    return $user;
}

=head2 get_user_by_cmd

Using the cmd_user command to determine any user/home 

=cut

sub get_user_by_cmd {
    my ( $self ) = @_;
    
    # get temp file
    my ( $th, $tn ) = $self->get_temp_file( $self->server->temp_dir, "file-XXXXXX" );
    
    # open pipe to command getting user, pipe output to tempfile
    open my $cmd_fh, '|-', $self->cmd_user. "1>\"$tn\"";
    $self->add_file_handle( $cmd_fh );
    
    # add the "to" to the prog returning the user
    print $cmd_fh $self->to;
    
    # close file, remove from list
    $self->close_file( $cmd_fh );
    $self->close_file( $th );
    
    my ( $user ) = <$th>;
    chomp $user;
    close $th;
    unlink( $tn ) if -f $tn;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

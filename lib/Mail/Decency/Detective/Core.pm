package Mail::Decency::Detective::Core;

use Mouse;
extends qw/
    Mail::Decency::MouseX::FullInherit
/;
with qw/
    Mail::Decency::Core::Module
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

Mail::Decency::Detective::Core

=head1 EXTENDS MODULES

=over

=item L<Mail::Decency::MouseX::FullInherit>

=back


=head1 WITH ROLES

=over

=item L<Mail::Decency::Core::Module>

=back

=head1 DESCRIPTION

Base class for all Detective modules


=head1 CLASS ATTRIBUTES

=head2 max_size : Int

Max size in bytes for an email to be checked.

=cut

has max_size => ( is => 'ro', isa => 'Int', default => 0 );

=head2 timeout : Int

Timeout for each Doorman module.

Default: 30

=cut

has timeout  => ( is => 'rw', isa => 'Int', default => 30 );


=head1 METHODS

=head2 before init

Adds max_size and timeout to config_param list

=cut

sub pre_init {
    shift->add_config_params( qw/ max_size timeout / );
}


=head2  file, file_size, mime

Convinient accessor to the server's session data 

=cut

sub file {
    return shift->session->current_file;
}
sub file_size {
    return shift->session->file_size;
}
sub mime {
    return shift->session->mime;
}

=head2 mime_has_changed

Announces a change in the MIME file.. See L<Mail::Decency::Core::SessionItem::Detective/mime_has_changed>

=cut

sub mime_has_changed {
    return shift->session->mime_has_changed;
}

=head2 mime_header

Header modificaton.. See L<Mail::Decency::Core::SessionItem::Detective/mime_header>

=cut

sub mime_header {
    return shift->session->mime_header( @_ );
}



=head2 exec_handle

Calls the handle method from the module

=cut

sub exec_handle {
    shift->handle( @_ );
}


=head2 init

=cut

sub init { die "'init' method has to be overwritten by ". ref( shift ) }

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

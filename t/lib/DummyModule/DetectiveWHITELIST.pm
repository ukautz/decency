package DummyModule::DetectiveWHITELIST;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Detective::Core::Spam
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

DummyModule::DoormanREJECT

=head1 DESCRIPTION

Dummy module for testing which forces REJECT reponse

=head1 METHODS

=head2 init

=cut

sub init {}

=head2 handle

=cut

sub handle {
    my ( $self ) = @_;
    $self->add_spam_score( 0, "This should not be seen" );
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

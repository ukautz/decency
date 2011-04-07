package DummyModule::PolicyOK;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Policy::Core
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

DummyModule::PolicyOK

=head1 DESCRIPTION

Dummy module for testing which forces OK reponse

=head1 METHODS

=head2 init

=cut

sub init {}

=head2 handle

=cut

sub handle {
    my ( $self ) = @_;
    $self->add_spam_score( 0, message_and_detail => 'All good, all the time' );
    $self->go_final_state( 'OK' );
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

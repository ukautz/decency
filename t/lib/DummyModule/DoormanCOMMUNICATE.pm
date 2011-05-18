package DummyModule::DoormanCOMMUNICATE;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

DummyModule::DoormanCOMMUNICATE

=head1 DESCRIPTION

Dummy module for testing which forces comunication between Doorman and Detective

=head1 ATTRIBUTES

=head2 score

=cut

has score => ( is => 'rw', isa => 'Num', default => 0 );

=head1 METHODS

=head2 init

=cut

sub init {
    my ( $self ) = @_;
    $self->score( $self->config->{ score } )
        if $self->config->{ score };
}

=head2 handle

=cut

sub handle {
    my ( $self ) = @_;
    $self->set_flag( 'doorman_was_here' );
    $self->add_spam_score( 33, message_and_detail => 'Got Score from Doorman' );
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

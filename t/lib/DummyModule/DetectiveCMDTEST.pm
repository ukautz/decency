package DummyModule::DetectiveCMDTEST;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Detective::Core::Cmd
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

DummyModule::DetectiveCOMMUNICATE

=head1 DESCRIPTION

Dummy module for testing communication betweenm Doorman and Detective

=head1 METHODS

=head2 init

=cut

sub init {}

=head2 handle

=cut

sub handle_filter_result {
    my ( $self, @args ) = @_;
    print "GOT CMD RESULT @args\n";
    $self->server->found_virus( );
}

sub get_user {
    return "";
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

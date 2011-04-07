package Mail::Decency::ContentFilter::AnyMilter;

use Mouse;
with qw/
    Mail::Decency::ContentFilter::Core::Milter
    Mail::Decency::ContentFilter::Core::Virus
/;

use version 0.74; our $VERSION = qv( "v0.1.9_1" );

use Mail::Decency::ContentFilter::Core::Constants;
use Data::Dumper;
use ClamAV::Client;
use Scalar::Util qw/ blessed /;

=head1 NAME

Mail::Decency::ContentFilter::AnyMilter

=head1 DESCRIPTION

Uses the L<Mail::Decency::ContentFilter::Core::Milter> and should be able to check against any regular sendmail compliant milter.

=head1 CLASS ATTRIBUTES

=cut


=head1 METHODS

=head2 init

=cut

sub init {}


=head2 handle

=cut

sub handle_filter_result {
    my ( $self, $result ) = @_;
    
    $self->logger->debug3( "Received result $file" );
    
    # return ok
    return CF_FILTER_OK;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

package Mail::Decency::Doorman::LiveStats;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
    Mail::Decency::Doorman::Model::LiveStats
/;
with qw/
    Mail::Decency::Core::LiveStats
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );


=head1 NAME

Mail::Decency::Doorman::LiveStats

=head1 DESCRIPTION

See L<Mail::Decency::Core::LiveStats>


=head1 METHODS

=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    foreach my $meth( qw/
        stream_log
        accumulate
    / ) {
        $self->$meth( $self->config->{ $meth } )
            if defined $self->config->{ $meth };
    }
    
    DD::cop_it "Require at least stream_log or accumulate\n"
        if ! $self->stream_log && ! $self->accumulate;
    
}


=head2 hook_finish

=cut

sub hook_finish {
    my ( $self, $status ) = @_;
    $self->update_live_stats( $status );
    return ( $status );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

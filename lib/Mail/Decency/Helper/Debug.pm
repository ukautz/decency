package Mail::Decency::Helper::Debug;

=head1 NAME

Mail::Decency::Helper::Debug

=head1 DESCRIPTION

This is a dirty way to use a shortcut for debug methods.

=head1 SYNOPSIS

    # print the debug mesage to STDERR
    $ENV{ DECENCY_DEBUG } = 1;
    DD::dbg( "Some Debug msg" );
    # DBG: Some Debug msg
    
    # die, either with confess (on debug) or carp
    $ENV{ DECENCY_DEBUG } = 1;
    DD::cop_it( "Some Debug msg" );
    
    # dump something on STDERRR

=cut

use strict;
use warnings;

package DD;

use Carp qw/ confess carp /;
use Data::Dumper;

$Carp::Internal{ (__PACKAGE__) }++;

sub dbg($) {
    return unless $ENV{ DECENCY_DEBUG };
    chomp $_[0];
    warn "DBG: $_[0]\n";
}

sub dmp($) {
    return unless $ENV{ DECENCY_DEBUG };
    warn Dumper( $_[0] );
}

sub dmpn($$) {
    return unless $ENV{ DECENCY_DEBUG };
    warn "**** $_[0] ****\n". Dumper( $_[1] ). "\n***********\n\n";
}

sub cop_it($) {
    my ( $ref ) = @_;
    die $ref if ref( $ref ) || eval '$ref->can( "isa" )';
    $ENV{ DECENCY_DEBUG } && confess( $_[0] );
    carp( $_[0] )
}

=head1 METHODS

=cut

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

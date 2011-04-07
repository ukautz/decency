package Mail::Decency::ContentFilter::Core::Spam;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

Mail::Decency::ContentFilter::Core::Spam

=head1 DESCRIPTION

For all modules being a spam filter (scoring mails)

=head1 CLASS ATTRIBUTES

=head2 weight_innocent : Int

Default weight of innocent mails.. used in descendant modules

=cut

has weight_innocent => ( is => 'rw', isa => 'Int', default => 10 );

=head2 weight_spam : Int

Default weight of spam mails .. used in descendant modules

=cut

has weight_spam     => ( is => 'rw', isa => 'Int', default => -50 );


=head1 METHOD MODIFIERS

=head2 before pre_init

Add check params: weight_innocent, weight_spam to list of check params

=cut

before pre_init => sub {
    shift->add_config_params( qw/ client_ident host port / );
};


=head1 METHODS

=head2 add_spam_score

    $self->add_spam_score( -10 => "Problem is xy" );

=cut

sub add_spam_score {
    my ( $self, $score, @info ) = @_;
    return $self->server->add_spam_score( $score, $self, @info );
}

=head2 add_spam_score

    $self->add_spam_score( -10 => "Problem is xy" );

=cut

around handle => sub {
    my ( $inner, $self ) = @_;
    
    # whitelisted ? Don't handle
    unless ( $self->has_flag( 'whitelisted' ) ) {
        return $self->$inner();
    }
    else {
        $self->add_spam_score( 0, "Skipped due to whitelisting" );
    }
};


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

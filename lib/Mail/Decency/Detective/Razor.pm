package Mail::Decency::Detective::Razor;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Detective::Core::Cmd
    Mail::Decency::Detective::Core::User
    Mail::Decency::Detective::Core::Spam
/;

use version 0.74; our $VERSION = qv( "v0.1.6" );

use Data::Dumper;

=head1 NAME

Mail::Decency::Detective::Razor

=head1 DESCRIPTION

Checks mails against the razor network.

=head2 CONFIG

    ---
    
    disable: 0
    #max_size: 0
    #timeout: 30
    
    #cmd_check: '/usr/bin/razor-check %file%'
    
    # weight for known innocent (good) mails
    weight_innocent: 10
    
    # weight for known spam (bad) mails
    weight_spam: -100
    


=head1 CLASS ATTRIBUTES

=cut

has cmd_check => (
    is      => 'rw',
    isa     => 'Str',
    default => '/usr/bin/razor-check %file%'
);

# has cmd_learn_spam => (
#     is      => 'rw',
#     isa     => 'Str',
#     default => '/usr/bin/razor-report %file%'
# );

# has cmd_unlearn_spam => (
#     is      => 'rw',
#     isa     => 'Str',
#     default => '/usr/bin/razor-revoke %file%'
# );


=head1 METHODS

=head2 init

=cut

sub init {
    my ( $self ) = @_;
    $self->config->{ disable_train } = 1;
}


=head2 handle_filter_result

=cut

sub handle_filter_result {
    my ( $self, $result, $exit_code ) = @_;
    
    # it is ham
    if ( $exit_code > 0 ) {
        return $self->add_spam_score( $self->weight_innocent => 'This is HAM' );
    }
    
    # it is spam
    else {
        return $self->add_spam_score( $self->weight_spam => 'This is SPAM' );
    }
    
    return ;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

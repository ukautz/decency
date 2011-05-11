package Mail::Decency::Doorman::CWL;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
    Mail::Decency::Doorman::Model::CWL
/;
with qw/
    Mail::Decency::Doorman::Core::CWLCBL
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );



use Data::Dumper;

=head1 NAME

Mail::Decency::Doorman::CWL

=head1 DESCRIPTION

See L<Mail::Decency::Doorman::Core::CWLCBL>

=head1 CONFIG

    ---
    
    disable: 0
    
    # enable negative cache
    use_negative_cache: 1
    
    # enable all tables
    tables:
        - ips
        - domains
        - addresses
    
    #deactivate_normal_list: 1
    #activate_sender_list: 1
    #activate_recipient_list: 1

=head1 METHODS

=head2 init

=cut

sub init {
    my ( $self ) = @_;
    $self->{ _handle_on_hit } = 'OK';
    $self->{ _table_prefix }  = 'cwl';
    $self->{ _description }   = 'Custom White List';
}

sub handle {}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

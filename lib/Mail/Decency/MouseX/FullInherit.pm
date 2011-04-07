package Mail::Decency::MouseX::FullInherit;

=head1 NAME

Module

=head1 DESCRIPTION

This module does ..

=head1 SYNOPSIS

    my $m = Module->new;

=cut

use Mouse;
use Mouse::Exporter;
use Scalar::Util qw/ refaddr /;

our @MODIFIERS = qw/ before around after /;


=head1 METHODS

=cut

#sub BUILD {}
#before BUILD => sub {
sub BUILD {
    my $self = shift;
    
    # get class and meta
    my $class = ref( $self );
    my $meta = $class->meta;
    
    # disabled ?
    return if $meta->{ _full_inherit_disabled } ||= 0;
    
    my %role_seen = map { ( $_->name => 1 ) } $meta->calculate_all_roles;
    Mouse::Util::apply_all_roles( $class, grep { ! $role_seen{ $_->name }++ } (
        map {
            $_->meta->calculate_all_roles
        } $meta->linearized_isa
    ) );
};

sub disable_full_inherit :method {
    my ( $class, $disable ) = @_;
    $class->meta->{ _full_inherit_disabled } = $disable ? 1 : 0;
}




=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

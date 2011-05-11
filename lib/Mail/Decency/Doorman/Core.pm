package Mail::Decency::Doorman::Core;

use Mouse;
use mro 'c3';
with qw/ Mail::Decency::Core::Module /;

use version 0.74; our $VERSION = qv( "v0.2.0" );
use Mail::Decency::Helper::IP qw/ is_local_host /;


=head1 NAME

Mail::Decency::Doorman::Core

=head1 DESCRIPTION

Base class for all Doorman modules.


=head1 CLASS ATTRIBUTES

=head2 timeout : Int

Timeout for each Doorman module.

Default: 15

=cut

has timeout  => ( is => 'rw', isa => 'Int', default => 15 );

=head2 handle_localhost : Bool

If enable, localhost IPs (127./8, ::1) will be handled as well. Otherwise they
will be ignored.

Not supported by all modules. See their description.

For some modules, data originating from localhost will mess things up.. eg Association will most likely think it is spam (as long as the domain does not point to 127.0.0.1..). 

Default: 0

=cut

has handle_localhost => ( is => 'rw', isa => 'Bool', default => 0 );


=head1 REQUIRED METHODS

=head1 METHOD MODIFIERS

=head2 pre_init

Adds params timeout and handle_localhost to config_params 

=cut

sub pre_init {
    shift->add_config_params( qw/ timeout handle_localhost / );
}

=head2 exec_handle

Calls the handle method from the module

=cut

sub exec_handle {
    my $self = shift;
    return if ! $self->handle_localhost() && is_local_host( $self->ip );
    return $self->handle( @_ );
}

=head1 METHODS

See also L<Mail::Decency::Core::Module>

=head2 init

Has to be overwritten by the module

=cut

sub init { die "'init' method has to be overwritten by ". ref( shift ) }


=head2 hostname

The sender HOSTNAME

=head2 helo

The sender HELO name

=head2 ip

The sender IP

=head2 sasl

The SASL username, if any

=head2 attrs

Access to all existing attributes (HashRef)

=cut

sub hostname { return shift->session->hostname }
sub helo     { return shift->session->helo }
sub ip       { return shift->session->ip }
sub sasl     { return shift->session->sasl }
sub attrs    { return shift->session->attrs }



=head2 add_spam_score $weight, %params

See L<Mail::Decency::Doorman>

=cut

sub add_spam_score {
    my ( $self, $weight, %params ) = @_;
    $self->server->add_spam_score( $self, $weight, %params );
}


=head2 go_final_state $state, $messsage

See L<Mail::Decency::Doorman>

=cut

sub go_final_state {
    my ( $self, @args ) = @_;
    $self->server->go_final_state( $self, @args );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

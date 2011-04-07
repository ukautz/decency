package Mail::Decency::Helper::Locker;

use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Fcntl ':flock';

=head1 NAME

Mail::Decency::Helper::Locker

=head1 DESCRIPTION

File Based locker class


=head2 new $file_template

Create new locker instance

=cut

sub new {
    my ( $class, $locker_template ) = @_;
    return bless {
        lockers => {},
        templ   => $locker_template
    }, $class;
}

sub DESTROY {
    my ( $self ) = @_;
    while( my ( $num, $fh ) = each %{ $self->{ lockers } } ) {
        close( $fh ) if $fh;
        my $file = $self->{ templ }. '.'. $num;
        unlink( $file ) if -f $file;
    }
}

=head2 lock

Lock a locker with given number

=cut

sub lock {
    my ( $self, $num ) = @_;
    $num //= 0;
    $self->unlock( $num );
    open my $fh, '>', $self->{ templ } . '.'. $num;
    flock( $fh, LOCK_EX );
    $self->{ lockers }->{ $num } = $fh;
    return ;
}

=head2 unlock $num

Unlock a locker with given number

=cut

sub unlock {
    my ( $self, $num ) = @_;
    $num //= 0;
    my $fh = $self->{ lockers }->{ $num } || undef;
    close( $fh ) if $fh;
    $self->{ lockers }->{ $num } = undef;
    return;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

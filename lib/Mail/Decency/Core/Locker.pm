package Mail::Decency::Core::Locker;

use Mouse::Role;
use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use Data::Pager;

use Time::HiRes qw/ usleep ualarm /;
use Carp qw/ confess /;

use Mail::Decency::Helper::Locker;

our $DEFAULT_DEADLOCK_TIMEOUT = 2_000_000;

=head1 NAME

Mail::Decency::Core::Locker

=head1 DESCRIPTION

Adds locker methods to servers which can be used from databases and so on.

=head1 SYNPOSIS

Create a new datbaase like this:

    Mail::Decency::Helper::Database->create( MongoDB => $config_ref );


=head1 CLASS ATTRIBUTES

=head2 lockers : HashRef[IPC::Semaphore]

=cut

has lockers => (
    is => "rw",
    isa => 'HashRef[Mail::Decency::Helper::Locker]',
    default => sub { {} }
);

=head2 locker_pids : HashRef[Int]

PID of process creating the semaphore

=cut

has locker_pids => ( is => "rw", isa => 'HashRef[Int]', default => sub { {} } );

=head2 locker_pids : HashRef[Int]

PID of process creating the semaphore

=cut

has locker_timeouts => ( is => "rw", isa => 'HashRef[Int]', default => sub { {} } );

=head2 locker_path : HashRef[Int]

Path to locker path

Default: /tmp/decency-locker

=cut

has locker_path => ( is => "rw", isa => 'Str', default => '/tmp/decency-locker' );


=head1 METHODS

=cut

before BUILD => sub {
    my ( $self ) = @_;
};

after DEMOLISH => sub {
    my ( $self ) = @_;
    foreach my $name( keys %{ $self->lockers } ) {
        delete $self->lockers->{ $name };
    }
};


=head2 set_locker

=cut

sub set_locker {
    my ( $self, $name, %args ) = @_;
    $name ||= 'default';
    
    my $locker = $args{ locker };
    if ( ref( $name ) ) {
        $locker = $name;
        $name = 'default';
    }
    
    # alreadythere ?
    if ( defined $self->lockers->{ $name }
        && ref( $self->lockers->{ $name } ) =~ /^Mail::Decency::Helper::Locker/
    ) {
        return $self->lockers->{ $name };
    }
    
    $ENV{ LOCKER_DEBUG } && warn "CREATE LOCKER in $$\n";
    
    # timeout
    my $timeout = $args{ timeout } || $DEFAULT_DEADLOCK_TIMEOUT;
    $timeout *= 1_000_000 if $timeout < 100_000;
    
    # create locker only for master process. others use the provided locker
    unless ( $locker ) {
        my $locker_file = $self->locker_path;
        if ( -d $locker_file ) {
            $locker_file .= sprintf( '/%s-%s.lock', $self->name, $name );
        }
        else {
            $locker_file .= sprintf( '-%s-%s.lock', $self->name, $name );
        }
        $locker = Mail::Decency::Helper::Locker->new( $locker_file );
    }
    
    $self->locker_timeouts->{ $name } = $timeout;
    return $self->lockers->{ $name } = $locker;
}

*locker = *set_locker;

=head2 do_lock

Locks via flock file

=cut

sub do_lock {
    my ( $self, $name, $num ) = @_;
    $num ||= 0;
    
    my $locker = $self->locker( $name )
        or die "No locker for '$name' found";
    
    # !! ATTENTION !!
    #   the purpose of this locking is to ensure increments in multi-forking
    #   environment work. The purpose is NOT to assure absolute mutual
    #   exclusion. 
    #   worst case for data: some counter are not incremented
    #   worst case for process: slow response (not to speak of deadlock)
    #   the process needs overrule the (statistic) data needs.
    # !! ATTENTION !!
    my $timeout = $self->locker_timeouts->{ $name } || $DEFAULT_DEADLOCK_TIMEOUT;
    my $deadlock = $timeout;
    eval {
        $SIG{ ALRM } = sub {
            die "Deadlock timeout in $name after $timeout\n";
        };
        ualarm( $deadlock );
        $locker->lock( $num );
    };
    ualarm( 0 );
    if ( $@ ) {
        warn "DEADLOCK IN $name, SEM $num\n";
    }
    $locker->unlock( $num );
}


=head2 do_unlock

Unlocks the flock

=cut

sub do_unlock {
    my ( $self, $name, $num ) = @_;
    $num ||= 0;
    my $locker = $self->locker( $name )
        or die "No locker for '$name' found";
    $locker->unlock( $num );
}

=head2 read_lock

Do read lock

=cut

sub read_lock {
    my ( $self, $name ) = @_;
    return $self->do_lock( $name, 1 );
}

=head2 read_unlock

Do unlock read

=cut

sub read_unlock {
    my ( $self, $name ) = @_;
    return $self->do_unlock( $name, 1 );
}



=head2 write_lock

Do read lock

=cut

sub write_lock {
    my ( $self, $name ) = @_;
    $self->read_lock( $name );
    $self->do_lock( $name, 2 );
    return ;
}

=head2 write_unlock

Do unlock read

=cut

sub write_unlock {
    my ( $self, $name ) = @_;
    $self->do_unlock( $name, 2 );
    $self->read_unlock( $name );
}

=head2 usr_lock

Custom locker

=cut

sub usr_lock {
    my ( $self, $name ) = @_;
    return $self->do_lock( $name, 0 );
}

=head2 usr_lock

Custom locker

=cut

sub usr_unlock {
    my ( $self, $name ) = @_;
    return $self->do_unlock( $name, 0 );
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;


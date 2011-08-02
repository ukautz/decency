package Mail::Decency::Core::Module;

use Mouse::Role;
with qw/ Mail::Decency::Core::Meta /;

use version 0.74; our $VERSION = qv( "v0.2.0" );
use File::Temp qw/ tempfile /;
use Scalar::Util qw/ weaken refaddr /;
use overload '""' => \&get_name;

=head1 NAME

Mail::Decency::Core::Module

=head1 DESCRIPTION

Base class for all modules (M::D::Doorman::*, M::D::Detective::*)

=cut

=head1 WITH ROLES

=over

=item L<Mail::Decency::Core::Meta>

=back

=cut

=head1 CLASS ATTRIBUTES

=head2 server

Backlink to the server

=cut

has server => ( is => 'rw', isa => 'Mail::Decency::Core::Server', required => 1, weak_ref => 1 );

=head2 config_params : ArrayRef[Str]

For easy module initialization, developers can set array of the config params. They will be set if they are defined.

    # do this
    has config_params => ( is => 'ro', isa => 'ArrayRef[Str]', default => sub { [ qw/ something / ] } );
    
    # an it will be initialized
    $self->something( $self->config->{ something } )
        if defined $self->config->{ something };

=cut

has config_params => (
    is        => 'ro',
    isa       => 'ArrayRef[Str]',
    predicate => 'has_config_params',
    traits    => [qw/ MouseX::NativeTraits::ArrayRef /],
    handles   => { add_config_params => 'push' },
    default   => sub { [] }
);


=head2 file_handles

List of possible not open filehandles. Will be closed by the exception checker

=cut

has file_handles => (
    is        => 'ro',
    isa       => 'HashRef',
    predicate => 'has_open_file_handles',
    traits    => [ qw/ MouseX::NativeTraits::HashRef / ],
    handles   => {
        get_open_file_handles => 'values',
    },
    default   => sub { {} }
);

=head2 timeout_child_kill_signal

SIGNAL used to kill timeout-ted processes (not the forked servers, but all processes started by a module) if the modules timeouts. Set to the INT value of the SIG (eg SIGKILL = 9, SIGHUP = 1) or the string value ( eg "USR1" for SIGUSR1 and so on). Use "man kill" to see all the signals.

Set to 0 to disable.

Default: 9 (SIGKILL)

=cut

has timeout_child_kill_signal => ( is => 'rw', isa => 'Str', default => 'KILL' );



=head1 REQUIRED METHODS

=head2 exec_handle

Each child method has to

=cut

requires qw/
    exec_handle
/;

=head1 METHOD MODIFIERS


=head2 after init

Read all params from config which are provided via "config_params" attribute (build up in pre_init and init phase)

=cut

after init => sub {
    my ( $self ) = @_;
    
    # no params ?
    return unless $self->has_config_params;
    
    # add params
    foreach my $attr( @{ $self->config_params } ) {
        $self->$attr( $self->config->{ $attr } )
            if $self->config->{ $attr };
    }
};



=head1 METHODS

=head2 clearup

=cut

sub clearup {
    my ( $self ) = @_;
    
    # empty file handles cache
    $self->clear_file_handles;
}

=head2 get_handlers

Return handlers as a single sub-ref

=cut

sub get_handlers {
    my ( $self ) = @_;
    
    # check wheter having config!
    DD::cop_it "No config has been set\n"
        unless $self->has_config;
    
    weaken( my $self_weak = $self );
    return sub {
        return $self_weak->handle( @_ );
    };
}

=head2 get_name

Used for the overloaded string context

=cut

sub get_name {
    return shift->name;
}


=head2 add_file_handle

Register file handle (eg: not opened via open_file method)

=cut

sub add_file_handle {
    my ( $self, $r ) = @_;
    my ( $fh, $file, $keep ) = __file_handle_ref( $r );
    $keep = 1 unless defined $keep; # assure we keep the file if just filehandle was added
    $self->file_handles->{ refaddr( $fh ) } = [ $fh, $file, $keep ];
    return $fh;
}

=head2 clear_file_handles

Clear all file handles by closing them.

=cut

sub clear_file_handles {
    my ( $self ) = @_;
    my @open = $self->get_open_file_handles;
    my @errors = ();
    foreach my $r( @open ) {
        my ( $fh, $fn, $keep ) = __file_handle_ref( $r );
        $self->close_file( $fh, 1 );
        unlink( $fn ) if $fn && ! $keep && -f $fn;
    }
    DD::cop_it join( " / ", @errors ) if @errors;
    return ;
}


=head2 get_temp_file

Creates temp file in given temp dir (or server->temp_dir, if any) and adds it to the open filehandles list so it can be closed even if the module failed

=cut

sub get_temp_file {
    my $self = shift;
    my ( $th, $tn ) = $self->__get_temp_file( @_ );
    $self->add_file_handle( [ $th, $tn, 0 ] );
    return ( $th, $tn );
}


=head2 get_static_file

Creates temp file in given temp dir (or server->temp_dir, if any) and adds it to the open filehandles list so it can be closed even if the module failed

=cut

sub get_static_file {
    my $self = shift;
    my ( $th, $tn ) = $self->__get_temp_file( @_ );
    $self->add_file_handle( [ $th, $tn, 1 ] );
    $tn =~ s#//+#/#g;
    return ( $th, $tn );
}

=head2 open_file

Opens a file, adds the file handle to the list, assures they are closed even if the module fails

=cut

sub open_file {
    my ( $self, $mode, $file, $msg ) = @_;
    $msg ||= "Failed to open file '$file' (mode '$mode', module: '$self'):";
    open my $fh, $mode, $file
        or DD::cop_it "$msg $@";
    $self->add_file_handle( [ $fh, $file ] );
    return $fh;
}

=head2 close_file

Opens a file, adds the file handle to the list, assures they are closed even if the module fails

=cut

sub close_file {
    my ( $self, $close_fh, $ignore_error ) = @_;
    my $addr = refaddr( $close_fh );
    if ( defined( my $r = delete $self->file_handles->{ $addr } ) ) {
        my ( $fh, $file, $keep ) = __file_handle_ref( $r );
        if ( $ignore_error ) {
            close $fh;
        }
        else {
            close $fh
                or DD::cop_it "Could not close file handle $addr". ( $file ? " ($file)" : "" ). ": $!";
        }
    }
    return ;
}




=head2 session

Access to current session data

=cut

sub session {
    return shift->server->session;
}

=head2 from, from_domain, from_prefix

The sender

=head2 to, to_domain, to_prefix

The recipient

=cut

sub from { return shift->session->from }
sub from_domain { return shift->session->from_domain }
sub from_prefix { return shift->session->from_prefix }

sub to { return shift->session->to }
sub to_domain { return shift->session->to_domain }
sub to_prefix { return shift->session->to_prefix }




=head2 (del|set|has)_flag

See L<Mail::Decency::Doorman::SessionItem>

=cut

sub set_flag { shift->session->set_flag( @_ ); }
sub has_flag { shift->session->has_flag( @_ ); }
sub del_flag { shift->session->del_flag( @_ ); }


=head2 database

=cut

sub database {
    return shift->server->database;
}





sub __get_temp_file {
    my ( $self, $temp_dir, $format, @args ) = @_;
    $temp_dir ||= $self->server->temp_dir if $self->server->can( 'temp_dir' );
    DD::cop_it "Require temp dir for get_temp_file"
        unless $temp_dir;
    $format ||= "file-XXXXXX";
    return tempfile( "$temp_dir/$format", UNLINK => 0, @args );
}

sub __file_handle_ref {
    my ( $r ) = @_;
    
    #my ( $fh, $file, $keep )
    return ref($r) =~ /ARRAY/ ? @$r : ( $r );
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

package Mail::Decency::Core::Meta;

use Mouse::Role;
#with qw/ Mail::Decency::MouseX::FullInherit /;
use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use Scalar::Util qw/ weaken blessed /;
use YAML qw/ LoadFile /;
use File::Basename qw/ dirname /;

=head1 NAME

Mail::Decency::Core::Meta

=head1 DESCRIPTION

Meta base class for most deceny modules.


=head1 CLASS ATTRIBUTES

See L<Mail::Decency::Doorman::Core>

=cut

has config     => ( is => 'rw', trigger => \&_init_config , predicate => 'has_config' );
has config_dir => ( is => 'rw', isa => 'Str', predicate => 'has_config_dir' );
has cache      => ( is => 'ro', isa => 'Mail::Decency::Helper::Cache', weak_ref => 1 );
has logger     => ( is => 'ro', isa => 'Mail::Decency::Helper::Logger' );
has name       => ( is => 'rw', isa => 'Str', default => sub {
    my ( $self ) = @_;
    ( my $name = lc( ref( $self ) ) ) =~ s/^.*:://;
    return $name;
} );

has __roles_inited => ( is => 'rw', isa => 'Bool', default => 0 );

=head1 REQUIRED METHODS

=head1 init

Have to be implemented by any server, module

=cut

requires qw/ init /;

=head1 METHOD MODIFIERS

=head2 after BUILD

Constructor chain

=cut

sub BUILD {}
after BUILD => sub {
    my ( $self ) = @_;
    
    # parse config
    $self->parse_config();
    
    # run pre-init phase
    $self->pre_init();
    
    # call init ..
    $self->init();
    
    # cleanup, check and such after init
    $self->after_init();
};


=head1 after DEMOLISH

Destructor chaing

=cut

sub DEMOLISH {}
after DEMOLISH => sub {
    my ( $self ) = @_;
    #warn "$$> DEMOLISH ". $self->name. "\n";
    $self->demolish() if $self->can( 'demolish' );
    my $logger = $self->logger
        ? $self->logger
        : ( $self->can( 'server' )
            ? $self->server->logger
            : undef
        )
    ;
    $logger->debug0( "Stopped ". $self->name ) if $logger;
};


=head1 METHODS

=cut



=head2 pre_init

Called before the init method. Can be overwritten by any module inheriting.

=cut

sub pre_init {}

=head2 after_init

Called after the init mehtod.

=cut

sub after_init {}


=head2 parse_config

Read config file , read includes ..

=cut

sub parse_config {
    my ( $self ) = @_;
    
    die "Config required\n"
        unless $self->config;
    
    # parse config -> find all "includes"
    if ( defined $self->config->{ include } ) {
        my @includes = ref( $self->config->{ include } )
            ? @{ $self->config->{ include } }
            : ( $self->config->{ include } )
        ;
        
        my %add = ();
        foreach my $include( @includes ) {
            my $path = ! -f $include && $self->has_config_dir
                ? $self->config_dir . "/$include"
                : $include
            ;
            die "Cannot include config file '$path': does not exist or not readable (". (
                $self->has_config_dir
                    ? "config_dir: ". $self->config_dir
                    : "no config_dir"
                ). ")\n"
                unless -f $path;
            %add = ( %add, %{ LoadFile( $path ) } );
        }
        
        # merge by replace
        $self->config( { %{ $self->config }, %add } );
    }
}


=head1 PRIVATE METHODS

=head2 _init_config

=cut

sub _init_config {
    my ( $self, $config_ref ) = @_;
    unless ( ref( $self->config ) ) {
        die "Require hashref or path to file for config, got '". $self->config. "'\n"
            unless -f $config_ref;
        
        # extract dir
        unless ( $self->has_config_dir ) {
            my $config_dir = dirname( $config_ref );
            $self->config_dir( $config_dir );
        }
        
        # load file from yaml
        $self->config( LoadFile( $config_ref ) );
    }
    
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

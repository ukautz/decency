package Mail::Decency::Core::Excludes;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use feature qw/ switch /;

=head1 NAME

Mail::Decency::Core::Excludes

=head1 DESCRIPTION

Excludes module handling per recipient/sender domain/address.

Those exlusions can be either defined in the configuration and/or a plain text file and/or the a database.

This extension uses heavily caching

=head1 CONFIG

In server config:

    ---
    
    exclusions:
        
        modules:
            
            DNSBL:
                from:
                    - bla@recipient.tld
                from_domain:
                    - sender.tld
                    - somedomain.tld
                to:
                    - some@sender.tld
                to_domain:
                    - recipient.tld
                    - anotherdomain.tld
        
        file: /etc/decency/exclusions.txt
        
        database: 1
    

=head2 EXCLUSION PLAIN TEXT FILE

like this:

    from_domain:dnsbl:sender.tld
    from_domain:dnsbl:somedomain.tld
    to_domain:geoweight:recipient.tld
    to_domain:geoweight:anotherdomain.tld
    to:spf:some@sender.tld
    from:spf:bla@recipient.tld

Module names have to be lower case

=head2 DATABASE

Module names have to be lower case

=head1 CLASS ATTRIBUTES

=head2 exclude_from_domain : HashRef[Bool]

=cut

has exclusions => ( is => 'rw', isa => 'HashRef[Bool]', predicate => 'enable_exclusions' );

=head2 enable_file : Str

If set: Plain text file in the format "type:module:value" eg "from:honeypot:some@domain.tld"

=cut

has exclusion_file => ( is => 'rw', isa => 'Str', predicate => 'enable_exclusion_file' );

=head2 exclusion_dir : Str

If set: Directory structure containing plain text files. The Structure is like so:

    <exclusion_dir>/<type>/<module>.txt

Example:

    /etc/decency/exclusions/from_domain/honeypot.txt

which contains:

    somedomain.tld
    otherdomain.tld

=cut

has exclusion_dir => ( is => 'rw', isa => 'Str', predicate => 'enable_exclusion_dir' );

=head2 enable_database : Bool

Wheter to use the database or not

Default: 0

=cut

has enable_database => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 exclusion_methods : ArrayRef[Str]

=cut

has exclusion_methods => ( is => 'rw', isa => 'ArrayRef[Str]', predicate => 'has_exclusions' );


our %EXCLUDES_TABLE = (
    module  => [ varchar => 32 ],
    type    => [ varchar => 20 ],
    value   => [ varchar => 255 ],
    -unique => [ qw/ module type value / ]
);

=head1 METHODS

=head2 after init

=cut

after init => sub {
    my ( $self ) = @_;
    
    return unless defined $self->config->{ exclusions };
    my @exclusion_methods = ();
    
    # having exclusions in configuration
    if ( defined( my $m_ref = $self->config->{ exclusions }->{ modules } ) ) {
        $self->exclusions( {} );
        while ( my ( $module, $t_ref ) = each %$m_ref ) {
            $module = lc( $module );
            $t_ref = [ $t_ref ] unless ref( $t_ref );
            while ( my ( $type, $values_ref ) = each %$t_ref ) {
                foreach my $v( @$values_ref ) {
                    $v = lc( $v );
                    $self->exclusions->{ "$type:$module:$v" } = 1;
                }
            }
        }
        push @exclusion_methods, '_get_exclude_from_config';
    }
    
    # enable database ..
    if ( $self->config->{ exclusions }->{ database } ) {
        $self->{ schema_definition } ||= {};
        $self->{ schema_definition }->{ exclusions } = {
            lc( $self->name ) => { %EXCLUDES_TABLE },
        };
        $self->enable_database( 1 );
        #$self->check_database( { lc( $self->name ) => { exclusions => \%EXCLUDES_TABLE } } );
        push @exclusion_methods, '_get_exclude_from_database';
    }
    
    # having a plaintext dir ..
    if ( defined( my $dir = $self->config->{ exclusions }->{ dir } ) ) {
        $dir = $self->config_dir. "/$dir"
            if ! -d $dir && $dir !~ /^\//;
        DD::cop_it "Exclusion dir '$dir' does not exist or not accessable\n"
            unless -d $dir;
        $self->exclusion_dir( $dir );
        push @exclusion_methods, '_get_exclude_from_dir';
    }
    
    # having a plaintext file ..
    if ( defined( my $file = $self->config->{ exclusions }->{ file } ) ) {
        $file = $self->config_dir. "/$file"
            if ! -f $file && $file !~ /^\//;
        DD::cop_it "Exclusion file '$file' does not exist or not accessable\n"
            unless -f $file;
        DD::cop_it "Exclusion file '$file' not readable\n"
            unless -r $file;
        open my $fh, '<', $file
            or DD::cop_it "Error opening exclusion file '$file': $@";
        close $fh;
        $self->exclusion_file( $file );
        push @exclusion_methods, '_get_exclude_from_file';
    }
    
    $self->exclusion_methods( \@exclusion_methods );
    
};

=head2 do_exclude

Returns bool wheter the current mail (session) shall overstep the current module

=cut

sub do_exclude {
    my ( $self, $module ) = @_;
    
    return unless $self->has_exclusions;
    
    my $session = $self->session;
    
    my @check = map {
        my $v = lc( $session->$_ );
        my $n = lc( $module->name );
        [
            "$_:$n:$v",
            [ $_, $n, $v ]
        ];
    } qw/ to to_domain from from_domain /;
    
    foreach my $check( @check ) {
        my $res = $self->cache->get( $check->[0] );
        return $res eq "OK"
            if $res;
    }
    
    my $cache;
    foreach my $check( @{ $self->exclusion_methods } ) {
        ( my $ok, $cache ) = $self->$check( \@check );
        if ( $ok ) {
            $self->cache->set( $cache => "OK" );
            return 1;
        }
    }
    $self->cache->set( $cache => "NOPE" ) if $cache;
}

=head2 _get_exclude_from_config

=cut

sub _get_exclude_from_config {
    my ( $self, $check_ref ) = @_;
    foreach my $check( @$check_ref ) {
        if ( defined $self->exclusions->{ $check->[0] } ) {
            return ( 1, $check->[0] );
        }
    }
    
    return;
}

=head2 _get_exclude_from_database

=cut

sub _get_exclude_from_database {
    my ( $self, $check_ref ) = @_;
    
    foreach my $check( @$check_ref ) {
        my ( $type, $module, $value ) =@{ $check->[1] };
        my $db_ref = $self->database->get( exclusions => $self->name => {
            type   => $type,
            module => $module,
            value  => $value,
        } );
        return ( 1, $check->[0] ) if $db_ref && $db_ref->{ value } eq $check->[1]->[2];
    }
    
    return;
}

=head2 _get_exclude_from_dir

=cut

sub _get_exclude_from_dir {
    my ( $self, $check_ref ) = @_;
    
    my ( $ok, $cache_name );
    my $fh;
    eval {
        
        CHECK_DIRS:
        foreach my $check( @$check_ref ) {
            my ( $type, $module, $value ) =@{ $check->[1] };
            
            my $file = $self->exclusion_dir. "/$type/$module.txt";
            unless ( -f $file ) {
                $self->logger->debug2( "Did not find exclusions file from dir '$file'" );
                next CHECK_DIRS;
            }
        
            open $fh, '<', $file 
                or DD::cop_it "Cannot open exclusions file '". $file. "': $!";
            
            while ( my $l = <$fh> ) {
                chomp $l;
                $l = lc( $l );
                if ( $value eq $l ) {
                    $ok++;
                    $cache_name = $check->[0];
                    last CHECK_DIRS;
                }
            }
            close $fh if $fh;
            undef $fh;
        }
    };
    close $fh if $fh;
    $self->logger->error( "Error in exclusions from dir: $@" ) if $@;
    
    return ( $ok, $cache_name );
}

=head2 _get_exclude_from_file

=cut

sub _get_exclude_from_file {
    my ( $self, $check_ref ) = @_;
    
    my ( $ok, $cache_name );
    my $fh;
    eval {
        open $fh, '<', $self->exclusion_file 
            or DD::cop_it "Cannot open exclusions file '". $self->exclusion_file. "': $!";
        
        CHECK_LINE:
        while ( my $l = <$fh> ) {
            chomp $l;
            $l = lc( $l );
            foreach my $check( @$check_ref ) {
                if ( $check->[0] eq $l ) {
                    $ok++;
                    $cache_name = $l;
                    last CHECK_LINE;
                }
            }
        }
    };
    close $fh if $fh;
    $self->logger->error( "Error in exclusions from file: $@" ) if $@;
    
    return ( $ok, $cache_name );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

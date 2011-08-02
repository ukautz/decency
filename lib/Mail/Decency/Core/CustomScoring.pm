package Mail::Decency::Core::CustomScoring;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Mail::Decency::Helper::IntervalParse qw/ interval_to_int /;

=head1 NAME

Mail::Decency::Core::Meta::CustomScoring

=head1 DESCRIPTION

Provide custom scoring per recipient or recipient domain. The idea
is that each mail user (or domain holder) can decide how loose or
harsh the threshold is.

=head1 CONFIG

In server config:

    ---
    
    custom_scoring:
        file: /path/to/file
        database: 1
        cache_timeout: 300


=head2 DATABASE

All domains 

=head1 CLASS ATTRIBUTES

=head2 enable_custom_scoring : Bool

Wheter enable or not

Default: 0

=cut

has enable_custom_scoring => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 custom_scoring_cache_timeout : Int

Timeout in seconds for the cache. Should be set according to the performance (eg
a mongodb -database is fast, whereas sqlite or a plain-text-file are slow) the
of the used sources.

Default: 300

=cut

has custom_scoring_cache_timeout => ( is => 'rw', isa => 'Int', default => 300 );


=head2 custom_scoring_file : Str

Filename for custom checks. Form at is

    recipient:value

Eg:

    user@domain.tld:-100
    domain.tld:-50

which implements a loose threshold for user@domain.tld, but a harsher threshold
for all other users off domain.tld.

All addresses should be placed before domains, cause it will accept the first match.

=cut

has custom_scoring_file => ( is => 'rw', isa => 'Bool', predicate => 'has_custom_scoring_file' );

=head2 _custom_scoring_methods : ArrayRef

Contains check methods beside cache

=cut

has _custom_scoring_methods => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );


our %CUSTOM_SCORING_TABLE = (
    recipient => [ varchar => 255 ],
    value     => 'integer',
    -unique   => [ qw/ recipient / ]
);

=head1 METHODS

=head2 after init

=cut

after init => sub {
    my ( $self ) = @_;
    
    return unless defined $self->config->{ custom_scoring };
    
    my $config_ref = $self->config->{ custom_scoring };
    my @check_methods;
    
    # use databsae ?
    if ( $config_ref->{ database } ) {
        $self->{ schema_definition } ||= {};
        $self->{ schema_definition }->{ custom_scoring } = {
            lc( $self->name ) => { %CUSTOM_SCORING_TABLE },
        };
        push @check_methods, '_custom_scoring_check_database';
    }
    
    # use file ?
    if ( my $file = $config_ref->{ file } ) {
        $self->custom_scoring_file( $file );
        push @check_methods, '_custom_scoring_check_file';
    }
    
    # any checks enabled ?
    if ( @check_methods ) {
        $self->_custom_scoring_methods( \@check_methods );
        $self->enable_custom_scoring( 1 );
    }
    
    # alter cache timeout
    $self->custom_scoring_cache_timeout( interval_to_int( $config_ref->{ cache_timeout } ) )
        if defined $config_ref->{ cache_timeout };
    
    return ;
};

=head2 custom_threshold_reached

Looks up custom thresholds. First address, then domain. If non found, it returns -1. Uses session to determine recipient

=cut

sub custom_threshold_reached {
    my ( $self, $spam_score, $to_address, $to_domain ) = @_;
    my $session = $self->session;
    $to_address ||= $session->to;
    $to_domain  ||= $session->to_domain;
    my $self_name = lc( $self->name );
    
    # consult caches
    my %cache = (
        $to_address => "custom_scoring:$self_name:$to_address",
        $to_domain  => "custom_scoring:$self_name:$to_domain"
    );
    foreach my $try( values %cache ) {
        my $cached = $self->cache->get( $try );
        return $cached if defined $cached;
    }
    
    # try all sources
    foreach my $meth( @{ $self->_custom_scoring_methods } ) {
        my ( $res, $name ) = $self->$meth( $spam_score, $to_address, $to_domain );
        if ( $res != -1 ) {
            $self->cache->set( $cache{ $name }, $res, $self->custom_scoring_cache_timeout );
            return $res;
        }
    }
    
    $self->cache->set( $_, -1, $self->custom_scoring_cache_timeout ) for values %cache;
    return -1;
}


=head2 _custom_scoring_check_database

Lookup database for thresholds

=cut

sub _custom_scoring_check_database {
    my ( $self, $spam_score, $to_address, $to_domain ) = @_;
    my $self_name = lc( $self->name );
    
    foreach my $try( $to_address, $to_domain ) {
        my $ref = $self->database->get( custom_scoring => $self_name => {
            recipient => $try
        } );
        if ( $ref && $ref->{ recipient } eq $try ) {
            my $res = $spam_score <= $ref->{ value } ? 1 : 0;
            return ( $res, $try );
        }
    }
    return ( -1 );
}


=head2 _custom_scoring_check_file

Lookup file for thresholds.

=cut

sub _custom_scoring_check_file {
    my ( $self, $spam_score, $to_address, $to_domain ) = @_;
    
    my %ok = ( $to_address => 1, $to_domain => 1 );
    my ( $fh, $name );
    my $res = -1;
    eval {
        open $fh, '<', $self->custom_scoring_file
            or DD::cop_it "Cannot open '". $self->custom_scoring_file. "' for read: $!";
        CHECK_FILE:
        while( my $l = <$fh> ) {
            chomp $l;
            next if ! $l || $l =~ /^\s*#/;
            my ( $recipient, $value ) = split( /\s*:\s*/, $l );
            if ( defined $ok{ $recipient } ) {
                $res = $spam_score <= $value ? 1 : 0;
                $name = $recipient;
                last CHECK_FILE;
            }
        }
    };
    my $err = $@;
    close $fh if $fh;
    DD::cop_it $err if $err;
    
    return ( $res, $name );
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

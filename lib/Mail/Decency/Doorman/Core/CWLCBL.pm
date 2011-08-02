package Mail::Decency::Doorman::Core::CWLCBL;


use Mouse::Role;
with qw/
    Mail::Decency::Core::Meta::Database
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );
use Mail::Decency::Helper::IP qw/ is_local_host /;
use Data::Dumper;

=head1 NAME

Mail::Decency::Doorman::Core::CWLCBL

=head1 DESCRIPTION

Implementation of custom whitelist or blacklist.

There are three kinds of lists:

=iver

=item * normal

This list is always a set of ( recipient domain, <from ip | from domain | from address> ), which allows to create white or blacklists per recipient domain.

=item * sender

With this list, you can etablish blacklists or whitelists from all sender sources to any (*) recipient domain. Think of this as global (black|white)lists (for all recipients).

=item * recipient

With this list, you can define rules for recipient domains only.

Eg, using this as blacklist, you can disallow your mail users to send to specific domains.

=back

=head2 PERFORMANCE

See L<Mail::Decency::Cookbook/Performance>

Strongly depends on the performance of your database.

=head3 Caching

If you use SQLite, you should use a fast cache. Using MongoDB (or anything fast): no need.

=cut

has _handle_on_hit  => ( is => 'ro', isa => 'Str' );
has _table_prefix   => ( is => 'ro', isa => 'Str' );
has _use_weight     => ( is => 'ro', isa => 'Bool' );
has _description    => ( is => 'ro', isa => 'Str' );
has _negative_cache => ( is => 'ro', isa => 'Bool', default => 0 );
has use_tables      => ( is => 'rw', isa => 'HashRef[Int]', default => sub { {} } );
has use_lists       => ( is => 'rw', isa => 'ArrayRef[SubRef]', default => sub { [] } );


=head1 METHODS

=head2 after init

Read config, init tables.

=cut

after init => sub {
    my ( $self ) = @_;
    
    my %tables_ok = map { ( $_ => 1 ) } qw/ ips domains addresses /;
    my @tables = defined $self->config->{ tables }
        ? @{ $self->config->{ tables } }
        : keys %tables_ok
    ;
    foreach my $table( @tables ) {
        DD::cop_it "Cannot use table '$table', please use only ". join( ", ", sort keys %tables_ok ). "\n"
            unless $tables_ok{ $table }
    }
    
    # negative cache ?
    $self->_negative_cache( 1 )
        if $self->config->{ negative_cache };
    
    # set tables
    $self->use_tables( { map { ( $_ => 1 ) } @tables } );
    
    # set lists
    push @{ $self->use_lists }, \&handle_normal_list
        unless $self->config->{ deactivate_normal_list };
    push @{ $self->use_lists }, \&handle_sender_list
        if $self->config->{ activate_sender_list };
    push @{ $self->use_lists }, \&handle_recipient_list
        if $self->config->{ activate_recipient_list };
    
    DD::cop_it "Require at least one list. Either dont deactivate the normal whitelist or acticate at least one of recipient or sender whitelist\n"
        if scalar @{ $self->use_lists } == 0;
};

=head2 around handle

Handle method for CWL or CBL.

=cut

around handle => sub  {
    my ( $inner, $self ) = @_;
    
    # don bother with loopback addresses! EVEN IF ENABLED BY FORCE!
    return if is_local_host( $self->ip );
    
    # is answer in cache ?
    my $cache_name = $self->name. "-". $self->cache->hash_to_name( {
        to_domain   => $self->to_domain,
        from_domain => $self->from_domain,
        ip          => $self->ip,
    } );
    if ( defined( my $cached = $self->cache->get( $cache_name ) ) ) {
        $self->cache_and_state( $cache_name, @$cached );
    }
    
    my @checks = ();
    foreach my $sub_ref( @{ $self->use_lists } ) {
        push @checks, $self->$sub_ref();
    }
    
    foreach my $check_ref( @checks ) {
        my ( $table, $attribs_ref, $name ) = @$check_ref;
        next unless $self->use_tables->{ $table };
        my $ref = $self->database->get( $self->_table_prefix => $table => $attribs_ref );
        $self->cache_and_state( $cache_name => $self->_handle_on_hit, $name ) if $ref;
    }
    
    
    # remember cached, if negative ok .. 
    $self->cache_and_state( $cache_name => 'DUNNO', "nohit" );
    
    return ;
};


=head1 METHODS


=head2 handle_normal_list

=cut

sub handle_normal_list {
    my ( $self ) = @_;
    return (
        [ ips => { to_domain => $self->to_domain, ip => $self->ip }, 'ip' ],
        [ domains => { to_domain => $self->to_domain, from_domain => $self->from_domain }, 'domain' ],
        [ addresses => { to_domain => $self->to_domain, from_address => $self->from }, 'address' ],
    );
}

=head2 handle_sender_list

=cut

sub handle_sender_list {
    my ( $self ) = @_;
    return (
        [ ips => { to_domain => '*', ip => $self->ip }, 'ip' ],
        [ domains => { to_domain => '*', from_domain => $self->from_domain }, 'domain' ],
        [ addresses => { to_domain => '*', from_address => $self->from }, 'address' ],
    );
}

=head2 handle_recipient_list

=cut

sub handle_recipient_list {
    my ( $self ) = @_;
    return (
        [ domains => { to_domain => $self->to_domain, from_domain => '*' }, 'address' ],
    );
}



=head2 cache_and_state

Do cache and call go_finale_state

=cut

sub cache_and_state {
    my ( $self, $cache_name, $state, $where ) = @_;
    
    my $final = $state ne 'DUNNO';
    
    # whitelist hit
    if ( $final && $state eq 'OK' && $self->_table_prefix eq 'cwl' ) {
        $self->set_flag( 'whitelisted' );
    }
    
    # save back to cache
    if ( $final || $self->_negative_cache ) {
        $self->cache->set( $cache_name => [ $state, $where ] );
    }
    
    $self->logger->debug0( "Got hit in $where: '". $self->from. "' -> '". $self->to. "': $state" )
        if $final;
    
    # set final state ..
    $self->go_final_state( $state, "Hit on ". $self->_description ) if $final;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

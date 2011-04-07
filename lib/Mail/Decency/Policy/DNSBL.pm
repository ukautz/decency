package Mail::Decency::Policy::DNSBL;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Policy::Core
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Net::DNSBL::Client;
use Data::Dumper;
use Mail::Decency::Helper::IP qw/ is_local_host /;
use Time::HiRes qw/ usleep /;

=head1 NAME

Mail::Decency::Policy::DNSBL

=head1 DESCRIPTION

Implementation of a DNS-based Blackhole List using L<Net::DNSBL::Client>.

=head2 CONFIG

    ---
    
    disable: 0
    
    harsh: 0
    
    blacklist:
        
        -
            host: ix.dnsbl.manitu.net
            weight: -100
        -
            host: psbl.surriel.com
            weight: -80
        -
            host: dnsbl.sorbs.net
            weight: -70
    

=head1 DESCRIPTION

Check external DNS blacklists (DNSBL). Allows weighting per blacklis or harsh policies (first hit serves).

=head2 PERFORMANCE

See L<Mail::Decency::Cookbook/Performance>

Performance depends on 


=head3 Caching

Should be enabled, either via your own DNS cache or via decency cache (not both), it will fasten things for reoccuring domains very much. If you use decency's cache, keep in mind that this can create a huge amount of cache entries and depending on your cache size the LRU (or whatever your cache uses) can render your cache useless.


=head1 CLASS ATTRIBUTES

=head2 blacklist

ArrayRef of blacklists

=head2 weight

HashRef of ( domain => weight ) for each blacklist

=head2 dnsbl

Instance of L<Net::DNSBL::Client>

=head2 harsh

Bool value determining wheter first blacklist hit rejects mail

=cut

has blacklist => ( is => 'rw', isa => 'ArrayRef[HashRef]', default => sub { [] } );
has weight    => ( is => 'rw', isa => 'HashRef[Int]', default => sub { {} } );
has dnsbl     => ( is => 'ro', isa => 'Net::DNSBL::Client' );
has harsh     => ( is => 'ro', isa => 'Bool' );

=head1 METHODS



=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    # @@@@@@@@@@@@@ TODO @@@@@@@@@@@@@@@@@@
    # >> Deactivate for localhost
    # >> Test performance of Net::DNS
    # @@@@@@@@@@@@@ TODO @@@@@@@@@@@@@@@@@@
    
    # check blacklists
    die "DNSBL: Require 'blacklist' as array\n"
        unless defined $self->config->{ blacklist }
        && ref( $self->config->{ blacklist } ) eq 'ARRAY';
    
    # build blacklists
    my $num = 1;
    my @blacklists = ();
    foreach my $ref( @{ $self->config->{ blacklist } } ) {
        die "DNSBL: Blacklist $num is not a hashref\n"
            unless ref( $ref ) eq 'HASH';
        push @blacklists, {
            domain => $ref->{ host }
        };
        $self->weight->{ $ref->{ host } } = $ref->{ weight } || -100;
        $num++;
    }
    
    # remember blacklists
    $self->blacklist( \@blacklists );
    
    # wheter use harash policy ?
    $self->{ harsh } = $self->config->{ harsh } || 0;
}


=head2 handle

Checks wheter incoming mail is whilist for final recipient

=cut

sub handle {
    my ( $self ) = @_;
    
    # setup new dnsbl client (each forked should have it's own!
    #$self->{ dnsbl } ||= Net::DNSBL::Client->new( { timeout => $self->config->{ timeout } || 3 } );
    
    my @reject_info;
    
    # go through all blacklists one bye one
    #   don't stress all blacklists, if not required!
    EACH_BLACKLIST:
    foreach my $list_ref( @{ $self->blacklist } ) {
        
        my $dnsbl = Net::DNSBL::Client->new( { timeout => $self->config->{ timeout } || 3 } );
        
        # query blacklist now
        my $max = 100;
        my $query_running = $dnsbl->query_is_in_flight;
        while ( $query_running && $max-- > 0 ) {
            usleep 50_000;
            $query_running = $dnsbl->query_is_in_flight;
        }
        if ( $query_running ) {
            $self->logger->error( "DNSBL client is in use. Cannot query $list_ref->{ domain }. Spawn more processes. Do not handle." );
            next EACH_BLACKLIST;
        }
        
        eval {
            $dnsbl->query_ip( $self->ip, [ $list_ref ] );
        };
        if ( $@ ) {
            if ( $@ =~ /Cannot issue new query while one is in flight/ ) {
                $self->logger->error( "DNSBL client is in use. Cannot query $list_ref->{ domain }. Spawn more processes. Do not handle." );
                next EACH_BLACKLIST;
            }
            else {
                $self->logger->error( "Error querying DNSBL client: $@" );
                next EACH_BLACKLIST;
            }
        }
        
        # retreive anwer
        my $result_ref = $dnsbl->get_answers;
        $result_ref = $result_ref->[0] if ref( $result_ref ) eq 'ARRAY';
        
        # any hit ??
        if ( $result_ref && ref( $result_ref ) eq 'HASH' && $result_ref->{ hit } ) {
            
            # collect weight
            my $add_weight = $self->weight->{ $list_ref->{ domain } } || 0;
            
            # log out ..
            $self->logger->debug0( "Hit on $list_ref->{ domain } for ". $self->ip. ", weight $add_weight ('". $self->from. "' -> '". $self->to. "')" );
            
            # update reject details..
            #push @reject_info, "$result_ref->{ domain }";
            #my $reject_info = "Blacklisted on ". join( ", ", @reject_info );
            my $reject_info = "Blacklisted on: ". $result_ref->{ domain };
            
            # add weight .. (throws exception if final state)
            $self->add_spam_score( $add_weight,
                message_and_detail => [ "$list_ref->{ domain }: hit ($add_weight)", $reject_info ] );
            
            # final state if harsh policy
            $self->go_final_state( REJECT => $reject_info ) if $self->harsh;
        }
        
        # no hit -> pass
        else {
            $self->logger->debug3( "Pass on $list_ref->{ domain } for ". $self->ip. " ('". $self->from. "' -> '". $self->to. "')" );
        }
        
        undef $dnsbl;
    }
    
    # add info that nothing has hit!
    unless ( @reject_info ) {
        $self->add_spam_score( 0, detail => "No hit on DNSBLs" );
    }
    
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

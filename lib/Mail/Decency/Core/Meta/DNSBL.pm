package Mail::Decency::Core::Meta::DNSBL;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );
use Net::DNSBL::Client;
use Time::HiRes qw/ usleep /;

=head1 NAME

Mail::Decency::Core::Meta::DNSBL

=head1 DESCRIPTION

DNSBL helper methods, shared by M:Doorman:DNSBL and M:Detective:DeepDNSBL

=head1 CLASS ATTRIBUTES


=head1 METHODS


=head2 check_dnsbls

Checks database by pinging (connection check) and setting up tables (schema definition)

=cut

sub check_dnsbls {
    my ( $self, $ip, $harsh ) = @_;
    
    my @reject_info;
    my $total_score = 0; 
    
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
            $dnsbl->query_ip( $ip, [ $list_ref ] );
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
            $self->logger->debug0( "Hit on $list_ref->{ domain } for ". $ip. ", weight $add_weight ('". $self->from. "' -> '". $self->to. "')" );
            
            # increment score
            $total_score += $add_weight;
            
            # add to reject score
            push @reject_info, $result_ref->{ domain };
            
            # final state if harsh policy
            return ( \@reject_info, $total_score, 1 ) if $harsh;
            
            # thats all wee need ?
            #print "X REACHED (". $self->server->spam_threshold. ") ". ( $self->server->spam_threshold_reached( $self->session->spam_score + $total_score ) ? "YES" : "NOE" ). "\n";
            last EACH_BLACKLIST
                if $self->server->spam_threshold_reached(
                    $total_score + $self->session->spam_score );
        }
        
        # no hit -> pass
        else {
            $self->logger->debug3( "Pass on $list_ref->{ domain } for ". $ip. " ('". $self->from. "' -> '". $self->to. "')" );
        }
        
        undef $dnsbl;
    }
    
    return ( \@reject_info, $total_score, 0 );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

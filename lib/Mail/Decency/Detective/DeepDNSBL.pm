package Mail::Decency::Detective::DeepDNSBL;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Core::Meta::DNSBL
    Mail::Decency::Detective::Core::Spam
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use Mail::Decency::Core::Exception;
use Net::DNSBL::Client;

=head1 NAME

Mail::Decency::Detective::DeepDNSBL

=head1 DESCRIPTION

Deep inspection of received header IPs and comparing against DNSBLs.

It works much like the L<Mail::Decency::Doorman::DNSBL> Module, but instead of using the connection IP, it tries to get all the IPs from the _Received_-header. The general idea is, that the mail might have been sent over a "good" MTA, but originated on a "bad" MTA (the spammer). Local network IPs (eg 10.0.0.0/8) will be ignored.

If a IP was checked by the DNSBL module from Doorman already, it will not be checked/weighted again.

Read also the Description section of the DNSBL module in Doorman (L<Mail::Decency::Doorman::DNSBL/Description>), where the pros and cons of DNSBLs are discussed.

=head1 CONFIG

    ---
    
    disable: 0
    timeout: 30
    
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
    
    

=head1 CLASS ATTRIBUTES


=head2 dnsbl : L<Net::DNSBL::Client>

Client requesting DNS black lists

=cut

has dnsbl => ( is => 'ro', isa => 'Net::DNSBL::Client' );

=head2 blacklist : ArrayRef[HashRef]

The actual blacklists with weighting

=cut

has blacklist => ( is => 'rw', isa => 'ArrayRef[HashRef]', default => sub { [] } );

=head2 weight : HashRef[Int]

Map of blacklist -> weight

=cut

has weight => ( is => 'rw', isa => 'HashRef[Int]', default => sub { {} } );


=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    # check blacklists
    DD::cop_it "DNSBL: Require 'blacklist' as array\n"
        unless defined $self->config->{ blacklist }
        && ref( $self->config->{ blacklist } ) eq 'ARRAY';
    
    # build blacklists
    my $num = 1;
    my @blacklists = ();
    foreach my $ref( @{ $self->config->{ blacklist } } ) {
        DD::cop_it "DNSBL: Blacklist $num is not a hashref\n"
            unless ref( $ref ) eq 'HASH';
        push @blacklists, {
            domain => $ref->{ host }
        };
        $self->weight->{ $ref->{ host } } = $ref->{ weight } || -100;
        $num++;
    }
    
    # remember blacklists
    $self->blacklist( \@blacklists );
}


=head2 handle

Archive file into archive folder

=cut


sub handle {
    my ( $self ) = @_;
    
    my ( $score, @reject_info ) = ( 0 );
    
    # check all found IPs
    foreach my $ip( @{ $self->session->ips } ) {
        
        # already checked this IP somewhere before ?
        next if $self->has_flag( 'dnsbl_ip_'. $ip );
        
        # set flag of the to be checked IP
        $self->set_flag( 'dnsbl_ip_'. $ip );
        
        # run check
        my ( $reject_ref, $score_add ) = $self->check_dnsbls( $ip );
        $score += $score_add;
        
        # thats all that it needs ?
        last if $self->server->spam_threshold_reached( $self->session->spam_score + $score );
    }
    
    # add score
    $self->add_spam_score( $score, ( @reject_info
        ? 'Blacklisted on '. join( ', ', @reject_info )
        : ''
    ) );
    
    return ;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

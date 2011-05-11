package Mail::Decency::Doorman::DNSBL;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
/;
with qw/
    Mail::Decency::Core::Meta::DNSBL
/;

use version 0.74; our $VERSION = qv( "v0.2.1" );

use Net::DNSBL::Client;
use Data::Dumper;
use Mail::Decency::Helper::IP qw/ is_local_host /;
use Time::HiRes qw/ usleep /;

=head1 NAME

Mail::Decency::Doorman::DNSBL

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
    
    # wheter use harash Doorman ?
    $self->{ harsh } = $self->config->{ harsh } || 0;
}


=head2 handle

Checks wheter incoming mail is whilist for final recipient

=cut

sub handle {
    my ( $self ) = @_;
    
    # already checked this IP somewhere before ?
    return if $this->has_flag( 'dnsbl_ip_'. $self->ip );
    
    # set flag of the to be checked IP
    $this->set_flag( 'dnsbl_ip_'. $self->ip );
    
    my ( $reject_ref, $add_score, $from_harsh )
        = $self->check_dnsbls( $self->ip, $self->harsh );
    
    my $reject_info = @$reject_ref
        ? 'Blacklisted on: '. join( ', ', @$reject_ref )
        : ''
    ;
    
    # using harsh hit ? end here
    $self->go_final_state( REJECT => $reject_info ) if $from_harsh;
    
    # add score, if any
    $self->add_spam_score( $add_score, message_and_detail => $reject_info );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

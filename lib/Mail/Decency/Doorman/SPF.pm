package Mail::Decency::Doorman::SPF;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Doorman::Core
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Mail::Decency::Helper::IP qw/ is_local_host /;
use Mail::SPF;
use Data::Dumper;

=head1 NAME

Mail::Decency::Doorman::SPF



=head1 DESCRIPTION

A SPF implementation (http://www.openspf.org/) for decency based on Mail::SPF

Weight's incoming mail based on the sender policy framework.

The SPF suggests that your (sender) domain has an additional TXT record providing a list/range of server ip's which are allowed to send mails.

For an explanation of the spf result codes have a look here: http://www.openspf.org/SPF_Received_Header

=head1 CONFIG

    ---
    versions: [ 1, 2 ]
    
    # the sender ip is allowed to send from this ip
    weight_pass: 20
    
    # no spf support from sender domain
    weight_none: 0
    
    # it is a fail, but sender domain admin has not the balls to use hard restrictions
    #   neutral is a bit more wishy-washy then softail is, but essentially both
    #   are saying: the particular sender is not really permitted, but it won't deny it
    #   the ..by_default neutral status i don't get..
    weight_neutral: -10
    weight_neutral_by_default: -10
    weight_softfail: -10
    
    # this admin has the bals. the sender ip is not permitted for this domain
    weight_fail: -50
    
    # some temporary dns problem. should not be weighted negativly, cause this
    #   could happen to any of us
    weight_temperror: 0
    
    # the permanent error says: we received something, but dont know what.
    weight_permerror: -10
    
    # this seems to catch error's which could not be further determined..
    weight_error: 0
    

=head2 CRITICS

Critics say the SPF could break existing structures, eg you cannot send mails from gmx.com via your company's mails server. Advocates reply: that's the idea and it is good.

=head1 CLASS ATTRIBUTES

=head2 versions : ArrayRef[Int]

What SPF Versions to use (actually there is no SPF version2, read http://www.openspf.org/SPF_vs_Sender_ID)

=cut

has versions => ( is => 'rw', isa => 'ArrayRef[Int]', default => sub { [ 1, 2 ] } );

=head2 weight_pass : Int

Weighting for passed (allowed) mails with correct SPF record

=cut

has weight_pass               => ( is => 'rw', isa => 'Int', default => 10 );

=head2 weight_pass : Int

Weighting for mails without any SPF record

=cut

has weight_none               => ( is => 'rw', isa => 'Int', default => 0 );

=head2 weight_neutral : Int

Weighting for neutral (probably not allowed, but not rejected)

=cut

has weight_neutral => ( is => 'rw', isa => 'Int', default =>  -20 );

=head2 weight_neutral_by_default : Int

Kind of the same as neutral

=cut

has weight_neutral_by_default => ( is => 'rw', isa => 'Int', default => -20 );

=head2 weight_softfail : Int

Soft fail.. kind of same as neutral

=cut

has weight_softfail => ( is => 'rw', isa => 'Int', default => -20 );

=head2 weight_fail : Int

Really failed. SPF records says: not allowed.

=cut

has weight_fail => ( is => 'rw', isa => 'Int', default => -50 );

=head2 weight_temperror : Int

Tempororay error.. maybe on your side ?

=cut

has weight_temperror => ( is => 'rw', isa => 'Int', default => 0 );

=head2 weight_permerror : Int

Permanent error.. should never happen. Something is really weird.

=cut

has weight_permerror => ( is => 'rw', isa => 'Int', default => -20 );

=head2 weight_error : Int

Some error.

=cut

has weight_error => ( is => 'rw', isa => 'Int', default => 0 );

=head2 spf_server : Mail::SPF::Server

=cut

has spf_server => ( is => 'rw', isa => 'Mail::SPF::Server' );


=head1 METHODS


=head2 init

=cut 

sub init {
    my ( $self ) = @_;
    
    # got versions ?
    if ( defined $self->config->{ versions } ) {
        die "versions has to be an arrayref of integers (1, 2 so far)\n"
            unless ref( $self->config->{ versions } ) eq 'ARRAY'
            && scalar grep { /^\d+$/ } @{ $self->config->{ versions } };
        $self->versions( $self->config->{ versions } );
    }
    
    # set weight
    foreach my $weight( qw/
        weight_pass
        weight_none
        weight_neutral
        weight_neutral_by_default
        weight_softfail
        weight_fail
        weight_temperror
        weight_permerror
        weight_error
    / ) {
        $self->$weight( $self->config->{ $weight } )
            if defined $self->config->{ $weight };
    }
    
    # init spf server
    $self->spf_server( Mail::SPF::Server->new );
    
    return ;
}


=head2 handle

=cut

sub handle {
    my ( $self ) = @_;
    
    # don bother with loopback addresses! EVEN IF ENABLED BY FORCE!
    return if is_local_host( $self->ip );
    
    # check mfrom scope
    if ( $self->from ) {
        $self->check_spf( mfrom => $self->from );
    }
    
    # check helo scope instead (eg bounce mail with empty mail from)
    else {
        $self->check_spf( helo => $self->helo );
    }
    
    # nothing to return
    return;
}



=head2 check_spf

Peforms the check for either helo or mfrom scope

=cut

sub check_spf {
    my ( $self, $scope, $identity ) = @_;
    my ( $code, $reject_message, $header, $weight );
    
    # found in cache ?
    my $cache_name = sprintf( 'SPF:%s:%s:%s', $scope, $identity, $self->ip );
    if ( defined( my $cached = $self->cache->get( $cache_name ) ) ) {
        ( $code, $reject_message, $header, $weight ) = @$cached;
    }
    
    # not found in cache, try
    else {
        
        # build request
        my $req = Mail::SPF::Request->new(
            versions   => $self->versions,
            scope      => $scope,
            identity   => $identity,
            ip_address => $self->ip
        );
        
        # send to spf server
        my $res = $self->spf_server->process( $req );
        
        # get code ..
        $code = $res->code;
        if ( $code ) {
            $code =~ s/-/_/g;
            
            # check wieght, if having..
            my $weight_meth = "weight_$code";
            if ( $self->can( $weight_meth ) ) {
                $self->logger->debug0( "Found SPF Result: $code for '". $self->from. "' / '". $self->ip. "'" );
                
                # parse headers, if any
                ( $header = $res->received_spf_header || "" ) =~ s/^Received-SPF: //;
                $reject_message = "";
                
                if ( $code =~ /^pass(?:ed)?/ ) {
                    $self->session->set_flag( 'spf_pass' );
                }
                elsif ( $code ne 'none' ) {
                    $self->session->set_flag( 'spf_nopass' );
                    $reject_message = "IP not on SPF Record for ". $self->from_domain;
                }
                
                $weight = $self->$weight_meth;
            }
            
            # oops, this should not happen
            else {
                $self->logger->error( "Malformed SPF result: $code for '". $self->from. "' from '". $self->ip. "'" );
            }
        }
    }
    
    # found result
    if ( $code ) {
        
        # write to cache
        $self->cache->set( $cache_name, [ $code, $reject_message, $header, $weight ] );
        
        # return scoring result (throws final exception, if final)
        return $self->add_spam_score( $weight,
            detail => join( "; ",
                "Result: $code",
                "Header: $header"
            ),
            message => $reject_message
        );
    }
    
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

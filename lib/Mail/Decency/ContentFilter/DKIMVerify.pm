package Mail::Decency::ContentFilter::DKIMVerify;

use Mouse;
extends qw/
    Mail::Decency::ContentFilter::Core
/;
with qw/
    Mail::Decency::ContentFilter::Core::Spam
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Mail::Decency::ContentFilter::Core::Constants;
use Mail::DKIM::Verifier;
use Data::Dumper;

=head1 NAME

Mail::Decency::ContentFilter::DKIMVerify

=head1 DESCRIPTION

Implement DKIM verification of incoming mails. Counter part would be DKIM signing of outgoing mails.


=head1 CONFIG

    ---
    DKIM:
        
        # signature present and fitting
        #weight_pass: 50
        
        # signature present, but incorrect
        #weight_fail: -100
        
        # signature malformed .. cannot be processed
        #weight_invalid: -50
        
        # some temporary error occured. Probably nothing bad
        #weight_temperror: -10
        
        # no key whats-o-ever found in mail, cannot verify
        #weight_none: 0

=head1 CLASS ATTRIBUTES


=head2 weight_pass : Int

Weight for passed mails with DKIM signature.

Default: 15

=cut

has weight_pass      => ( is => 'rw', isa => 'Int', default => 15 );

=head2 weight_fail : Int

Weight for failed mails with DKIM signature.

Default: -50

=cut

has weight_fail      => ( is => 'rw', isa => 'Int', default => -50 );

=head2 weight_invalid : Int

Weight for mails with an invalid (not failed) DKIM signature.

Default: -25

=cut

has weight_invalid   => ( is => 'rw', isa => 'Int', default => -25 );

=head2 weight_temperror : Int

Weight if DKIM signature cannot be verified temporary (eg the DKIM zone record cannot be retreived)

Default: 0

=cut

has weight_temperror => ( is => 'rw', isa => 'Int', default => 0 );

=head2 weight_none : Int

Weight for mails without any DKIM signature.

Default: 0

=cut

has weight_none      => ( is => 'rw', isa => 'Int', default => 0 );


=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    $self->add_config_params( qw/ weight_pass weight_fail weight_invalid weight_temperror weight_none / );
}


=head2 handle

Default handling for any content filter is getting info about the to be filterd file

=cut


sub handle {
    my ( $self ) = @_;
    
    # open file for read
    my $fh = $self->open_file( '<', $self->file, "Cannot open MIME file for DKIM read" );
    $self->add_file_handle( $fh );
    
    # init verifier and load file
    my $verifier = Mail::DKIM::Verifier->new;
    #$verifier->load( $fh );
    while( <$fh> ) {
        chomp;
        s/\015\012?$//;
        $verifier->PRINT( "$_\015\012" );
    }
    
    # close verifier and file
    close $fh;
    $verifier->CLOSE;
    
    # get result
    my $res = $verifier->result;
    
    # handle result, if found
    if ( $res && ( my $meth = $self->can( "weight_$res" ) ) ) {
        $self->logger->debug2( "Got result '$res'" );
        return $self->add_spam_score( $self->$meth, [ "Result: ". $verifier->result_detail ] );
    }
    else {
        $self->logger->error( "Unknown DKIM result '$res'" );
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

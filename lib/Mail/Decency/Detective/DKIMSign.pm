package Mail::Decency::Detective::DKIMSign;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Detective::Core::Spam
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Mail::Decency::Detective::Core::Constants;
use Mail::DKIM::Signer;

=head1 NAME

Mail::Decency::Detective::DKIMSign

=head1 DESCRIPTION

This module can be used for signing OR verifying mails. DONT USE BOTH IN THE SAME INSTANCE!!

=head1 CONFIG

    ---
    
    disable: 0
    #max_size: 0
    #timeout: 30
    
    # the default key. can be used only or as fallback
    sign_key: /etc/decency/dkim/default.key
    
    # a directory where the keys per (sender) domain are. 
    #   /etc/dkim/some-domain.co.uk.key
    #   /etc/dkim/other-domain.com.key
    sign_key_dir: /etc/decency/dkim/domains
    
    # the algorithmus and method .. change if you know what you are doing
    #sign_algo: rsa-sha1
    #sign_method: relaxed
    
    # additional sign headers
    additional_headers:
        - X-Mailer


=head1 CLASS ATTRIBUTES

=head2 sign_key : Str

Path to single sign key. If sign directory is set as well, this will be used as fallback.

=cut

has sign_key => ( is => 'rw', isa => 'Str', predicate => 'has_sign_key' );

=head2 sign_key_dir : Str

Path to a directory containing sign keys named by domain.. example:

    /path/to/sign-dir/mydomain.tld.key
    /path/to/sign-dir/otherdomain.tld.key

If any key is found it will take precedence over the default (sign_key).

=cut

has sign_key_dir => ( is => 'rw', isa => 'Str', predicate => 'has_sign_key_dir' );

=head2 sign_algo : Str

Which sign algorithm to use.

Default: rsa-sha1

=cut

has sign_algo => ( is => 'rw', isa => 'Str', default => 'rsa-sha256' );

=head2 sign_method : Str

Which sign method to use.

Default: relaxed

=cut

has sign_method => ( is => 'rw', isa => 'Str', default => 'relaxed' );

=head2 additional_headers : Str

Additional headers, apart from the suggested default headers(See section 5.5 in http://www.ietf.org/rfc/rfc4871.txt)

=cut

has additional_headers => ( is => 'rw', isa => 'Str', default => '' );

=head2 _signer : HashRef[Mail::DKIM::Signer]

Cache for L<Mail::DKIM::Signer>, per domain and keyfile (keyfiles can be added / replaced at runtime .. for replacing, assure the change time of the keyfile is updated).

=cut

has _signer => ( is => 'rw', isa => 'HashRef[Mail::DKIM::Signer]', default =>  sub { {} } );



=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    # having sign key
    if ( $self->config->{ sign_key } ) {
        DD::cop_it "Sign key '". $self->config->{ sign_key }. "' does not exist or not readable\n"
            unless -f $self->config->{ sign_key };
        $self->sign_key( $self->config->{ sign_key } )
    }
    
    # having sign key dir (domain.tld.key)
    if ( $self->config->{ sign_key_dir } ) {
        DD::cop_it "Sign key dir '". $self->config->{ sign_key_dir }. "' is not a directory or not readable\n"
            unless -d $self->config->{ sign_key_dir };
        $self->sign_key_dir( $self->config->{ sign_key_dir } )
    }
    
    # at least one
    DD::cop_it "Require 'sign_key' and/or 'sign_key_dir'\n"
        unless $self->has_sign_key || $self->has_sign_key_dir;
    
    if ( my $add_headers = $self->config->{ additional_headers } ) {
        $add_headers = join( ':', @$add_headers ) if ref( $add_headers );
        $self->additional_headers( $add_headers );
    }
    
    # update other args
    $self->add_config_params( qw/ sign_algo sign_method / );
}


=head2 handle

Default handling for any Detective is getting info about the to be filterd file

=cut


sub handle {
    my ( $self ) = @_;
    
    # determine domain
    my $domain = $self->from_domain;
    
    # determine key file (having dir, trye "domain.tld.key" there, then fallback to normal)
    my $key_file = $self->has_sign_key_dir && -f $self->sign_key_dir . "/${domain}.key"
        ? $self->sign_key_dir . "/${domain}.key"
        : $self->sign_key
    ;
    
    # no key file defined
    unless ( $key_file ) {
        $self->logger->debug2( "Could not determine key file for '$domain'" );
        return ;
    }
    
    # key file not existing
    elsif ( ! -f $key_file ) {
        $self->logger->error( "Key file '$key_file' does not exist" );
        return ;
    }
    
    # found key file
    $self->logger->debug2( "Sign mail from '". $self->from. "' to '". $self->to. "' with '$key_file'" );
    
    # create new signer
    my $timestamp = ( stat( $key_file ) )[9];
    my $signer = $self->_signer->{ $domain, $key_file, $timestamp } ||= Mail::DKIM::Signer->new(
        Algorithm => $self->sign_algo,
        Method    => $self->sign_method,
        Domain    => $domain,
        KeyFile   => $key_file,
        Headers   => $self->additional_headers
    );
    
    # open file and load into signer
    my $fh = $self->open_file( '<', $self->file );
    $signer->load( $fh );
    
    # close both
    $self->close_file( $fh );
    $signer->CLOSE;
    
    # update header in mime
    my ( $name, $value ) = split( /:/, $signer->signature->as_string, 2 );
    $self->mime_header( replace => $name, $value );
    
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

package Mail::Decency::Core::SessionItem::Doorman;

use Mouse;
extends qw/
    Mail::Decency::Core::SessionItem
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use MIME::QuotedPrint;

=head1 NAME

Mail::Decency::Core::SessionItem

=head1 DESCRIPTION

Represents an session item for either Doorman or Detective.
Base class, don't instantiate!

=head1 CLASS ATTRIBUTES

=head2 ip

The sender ip (client_address)

=cut

has ip => ( is => 'rw', isa => "Str" );

=head2 hostname

The sender hostname (client_name)

=cut

has hostname => ( is => 'rw', isa => "Str" );

=head2 helo

The sender helo name (helo_name)

=cut

has helo => ( is => 'rw', isa => "Str" );

=head2 sasl

The SASL username, if any

=cut

has sasl => ( is => 'rw', isa => "Str" );

=head2 attrs

All attributes from mail server

=cut

has attrs => ( is => 'rw', isa => "HashRef", default => sub { {} } );

=head2 response

The current final response .. defaults to "DUNNO"

=cut

has response => ( is => 'rw', isa => "Str", default => "DUNNO" );

=head2 message

List of messages for response line. Build of both: negative (such as "blacklisted on xy") or positive (such as "spf ok")

=cut

has message => (
    is      => 'rw',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
    traits  => [ qw/ Array / ],
    handles => {
        message_str    => 'join',
        has_no_message => 'is_empty'
    }
);

=head2 sign_key

Instance of L<Crypt::OpenSSL::RSA> representing the forward sign key

=cut

has sign_key => ( is => 'rw', isa => 'Crypt::OpenSSL::RSA', predicate => 'can_sign' );


=head1 METHODS

=head2 for_cache

Returns hashref which can be cached

=cut

sub for_cache {
    my ( $self ) = @_;
    
    return {
        spam_score   => $self->spam_score,
        spam_details => $self->spam_details,
        flags        => $self->flags,
        message      => $self->message,
        identifier   => $self->identifier
    };
}

=head2 update_from_cache

Updates current session from cached session

=cut

sub update_from_cache {
    my ( $self, $hash_ref ) = @_;
    
    $self->spam_score( $self->spam_score + $hash_ref->{ spam_score } )
        if $hash_ref->{ spam_score };
    
    $self->identifier( $hash_ref->{ identifier } )
        if $hash_ref->{ identifier };
    
    foreach my $msg( qw/ spam_details message / ) {
        my $add = "add_$msg";
        my $msg_ref = defined $hash_ref->{ $msg } && ref( $hash_ref->{ $msg } ) eq 'ARRAY'
            ? $hash_ref->{ $msg }
            : []
        ;
        #push $self->$add( @$msg_ref ) if $#$msg_ref > -1;
    }
    
    if ( $hash_ref->{ flags } ) {
        $self->set_flag( $_ ) for keys %{ $hash_ref->{ flags } };
    }
    
    return;
}

=head2 generate_instance_header

Returns the instance header.. if forwarding should be forwarded and has sign key, it will be signed

=cut

sub generate_instance_header {
    my ( $self, $forward_scoring ) = @_;
    
    my $sign_error;
    
    # shall we forward scoring ?
    my $add = "";
    if ( $forward_scoring ) {
        my @add = ();
        
        # 0: weight
        push @add, $self->spam_score;
        
        # 1: timestap
        push @add, time();
        
        # 2: states, sep by ","
        push @add, join( ',', sort keys %{ $self->flags } );
        
        # 3-n: details sep by |
        push @add, join( '|', @{ $self->spam_details } );
        
        # signing
        #   sign all values added before with key
        if ( $self->can_sign ) {
            my $signed_header = 'sign-failed';
            
            # catch error, don't interrupt the whole process
            eval {
                $signed_header = unpack( 'H*',
                    $self->sign_key->sign( join( '|', $self->id, @add ) ) );
            };
            $sign_error = $@;
            unshift @add, $signed_header;
        }
        
        # not signed
        else {
            unshift @add, 'unsigned';
        }
        
        $add = '|'. join( '|', @add );
    }
    
    #join( CRLF. "\t", split( /\n/, $header )
    
    #return ( encode_qp( $self->id. $add ), $sign_error );
    return ( $self->id. $add, $sign_error );
}


=head2 cleanup

Called at the very end of the session

=cut

sub cleanup {
    my ( $self ) = @_;
    $self->unset;
    return ;
}


=head2 add_message

Add message

=cut

sub add_message {
    my ( $self, @msg ) = @_;
    foreach my $msg( @msg ) {
        next unless $msg;
        push @{ $self->message }, ( ref( $msg )
            ? @$msg
            : ( $msg )
        );
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

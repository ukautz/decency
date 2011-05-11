package Mail::Decency::Detective::MimeAttribs;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;

=head1 NAME

Mail::Decency::Detective::MimeAttribs

=head1 DESCRIPTION

Simple mime manipulation. Be careful, can break DKIM or alike.

=head1 CONFIG

    ---
    
    disable: 0
    #max_size: 0
    #timeout: 30
    
    add_header:
        'X-SomeHeader': "Some Value"
        'X-OtherHeader': "Other Value"
    
    set_header:
        'X-Mailer': "My Company v0.1"
    
    replace_header:
        'X-DSPAM': "replaced"
    
    remove_header:
        - 'Subject'
    


=head1 CLASS ATTRIBUTES

=head2 add_header : HashRef

Add headers to mail .. if header already existing, it will be added also

=cut

has add_header     => ( is => 'rw', isa => 'HashRef', predicate => 'has_add_header' );

=head2 set_header : HashRef

Set's a header. If exists, it will be overwritten.

=cut

has set_header     => ( is => 'rw', isa => 'HashRef', predicate => 'has_set_header' );

=head2 replace_header : HashRef

Replaces a header. If not existing, nothing will be written

=cut

has replace_header => ( is => 'rw', isa => 'HashRef', predicate => 'has_replace_header' );

=head2 remove_header : ArrayRef[Str]

Removes a header, if it exists.

=cut

has remove_header  => ( is => 'rw', isa => 'ArrayRef[Str]', predicate => 'has_remove_header' );


=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    foreach my $meth( qw/
        add_header
        set_header
        replace_header
        remove_header
    / ) {
        $self->$meth( $self->config->{ $meth } )
            if $self->config->{ $meth };
    }
}


=head2 handle

Change MIME attributes as defined in the configuration

=cut


sub handle {
    my ( $self ) = @_;
    
    $self->logger->debug2( "Here we go.." );
    
    # add new headers
    if ( $self->has_add_header ) {
        while ( my ( $name, $value ) = each %{ $self->add_header } ) {
            $self->mime_header( add => $name => $value );
        }
    }
    
    # remove headers
    if ( $self->has_remove_header ) {
        foreach my $name( @{ $self->remove_header } ) {
            $self->mime_header( delete => $name );
        }
    }
    
    # set headers (add or replace)
    if ( $self->has_set_header ) {
        while ( my ( $name, $value ) = each %{ $self->set_header } ) {
            my $val = $self->mime_header( get => $name );
            unless ( $val ) {
                $self->mime_header( add => $name => $value );
            }
            else {
                $value =~ s/%orig%/$val/g;
                $self->mime_header( replace => $name => $value );
            }
        }
    }
    
    # replace headers
    if ( $self->has_replace_header ) {
        while ( my ( $name, $value ) = each %{ $self->replace_header } ) {
            my $val = $self->mime_header( get => $name );
            next unless $val;
            $value =~ s/%orig%/$val/g;
            $self->mime_header( replace => $name => $value );
        }
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

package Mail::Decency::Core::SessionItem;

use Mouse;
use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

Mail::Decency::Core::SessionItem

=head1 DESCRIPTION

Represents an session item for either Doorman or Detective.
Base class, don't instantiate!

=head1 CLASS ATTRIBUTES

=head2 id : Str

The primary identifier

=cut

has id => ( is => 'rw', isa => "Str", required => 1 );

=head2 spam_score : Num

Current spam score

=cut

has spam_score => ( is => 'rw', isa => 'Num', default => 0 );

=head2 spam_details : ArrayRef

List of details for spam. Those will be put in the header (unless deactivated)

=cut

has spam_details => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
    traits  => [ qw/ Array / ],
    handles => {
        has_no_spam_details => 'is_empty',
        add_spam_details    => 'push'
    }
);

=head2 flags : HashRef[Int]

Hashref of flags which can be set

=cut

has flags => ( is => 'rw', isa => 'HashRef[Int]', default => sub { {} } );

=head2 vals : HashRef

Hashref of session values with contents .. only for current session, will not be transported!

=cut

has vals => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

=head2 cache : Mail::Decency::Helper::Cache

Accessor to the parentl cache

=cut

has cache => ( is => 'rw', isa => 'Mail::Decency::Helper::Cache', required => 1, weak_ref => 1 );

=head2 from : Str

Sender of the current mail

=cut

has from => ( is => 'rw', isa => "Str", trigger => sub {
    my ( $self, $from ) = @_;
    my ( $prefix, $domain ) = split( /\@/, $from || "" );
    $self->from_prefix( $prefix || "" ) if $prefix;
    $self->from_domain( $domain || "" ) if $domain;
} );

=head2 from_prefix : Str

The prefix part of the mail FROM

=cut

has from_prefix => ( is => 'rw', isa => "Str" );

=head2 from_domain : Str

The domain part of the mail FROM

=cut

has from_domain => ( is => 'rw', isa => "Str" );

=head2 orig_to : Str

Recipient of the current mail

=cut

has orig_to => ( is => 'rw', isa => "Str" );

=head2 to : Str

Recipient of the current mail

=cut

has to => ( is => 'rw', isa => "Str", trigger => sub {
    my ( $self, $to ) = @_;
    my ( $prefix, $domain ) = split( /\@/, $to || "" );
    
    # check delimiter
    my $delimiter = $self->recipient_delimiter;
    if ( $delimiter && $prefix =~ /^(.+?)\Q$delimiter\E/ ) {
        my $before = $1;
        $self->orig_to( $to );
        return $self->to( $before . '@'. $domain );
    }
    
    # no orig_to until here -> set now
    elsif ( ! $self->orig_to ) {
        $self->orig_to( $to );
    }
    $self->to_prefix( $prefix || "" ) if $prefix;
    $self->to_domain( $domain || "" ) if $domain;
} );

=head2 to_prefix : Str

The prefix part ot the RCPT TO

=cut

has to_prefix => ( is => 'rw', isa => "Str" );

=head2 to_domain : Str

The domain part ot the RCPT TO

=cut

has to_domain => ( is => 'rw', isa => "Str" );

=head2 identifier : Str


=cut

has identifier => ( is => 'rw', isa => "Str", default => sub {
    my ( $self ) = @_;
    my @s = ( substr( time(). '', -4 ) );
    my @w = ( 'a'..'z', 0..9 );
    my $w = scalar @w;
    srand( time ^ $$ );
    foreach my $n( 0.. 12 ) {
        srand();
        push @s, $w[ int(rand()*$w) ];
    }
    return join( '', @s );
} );

=head2 recipient_delimiter : Str

See L<Mail::Decency::Core::Server/recipient_delimiter>

=cut

has recipient_delimiter => ( is => 'rw', isa => 'Str', default => '' );

=head1 METHODS

=head2 BUILD

=cut

sub BUILD {
    my ( $self ) = @_;
    $self->spam_details( [] ) unless $self->spam_details;
}

=head2 add_spam_score

add score 

=cut

sub add_spam_score {
    my ( $self, $add ) = @_;
    return $self->spam_score( $self->spam_score + $add );
}



=head2 (del|set|has)_flag

Set, remove or query wheter has flag

=cut

sub has_flag {
    my ( $self, $flag ) = @_;
    return defined $self->flags->{ $flag };
}

sub set_flag {
    my ( $self, $flag ) = @_;
    return $self->flags->{ $flag } = 1;
}

sub del_flag {
    my ( $self, $flag ) = @_;
    return delete $self->flags->{ $flag };
}

=head2 (del|set|get)_val

Set / delete /get session value

=cut

sub get_val {
    my ( $self, $val ) = @_;
    return $self->vals->{ $val };
}

sub set_val {
    my ( $self, $val, $v ) = @_;
    return $self->vals->{ $val } = $v;
}

sub del_val {
    my ( $self, $val ) = @_;
    return delete $self->vals->{ $val };
}


=head2 unset

=cut

sub unset {
    my ( $self ) = @_;
    delete $self->{ $_ } for keys %$self
}



=head2 spam_details_str

=cut

sub spam_details_str {
    my ( $self, $join ) = @_;
    my $ref = $self->spam_details || [];
    return join( $join, @$ref );
}

=head2 has_no_spam_detailsX

=cut

sub has_no_spam_detailsX {
    my ( $self ) = @_;
    my $ref = $self->spam_details || [];
    return $#$ref == -1;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

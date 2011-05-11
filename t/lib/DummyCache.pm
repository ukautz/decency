package DummyCache;

use strict;

sub new {
    return bless {
        data => {},
    }, $_[0];
}

sub get {
    my ( $self, $key ) = @_;
    $self->{ data }->{ $key };
}

sub set {
    my ( $self, $key, $val ) = @_;
    return $self->{ data }->{ $key } = $val; 
}

1;

package Mail::Decency::Policy::Model::GeoWeight;

=head1 NAME

Mail::Decency::Policy::Model::GeoWeight - Schema definition for GeoWeight

=head1 DESCRIPTION

Implements schema definition for GeoWeight

=cut

use strict;
use warnings;
use Mouse;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 DATABASE

    CREATE TABLE GEO_STATS (country varchar(2), counter integer, interval varchar(25), id INTEGER PRIMARY KEY);
    CREATE UNIQUE INDEX GEO_STATS_COUNTRY_INTERVAL ON GEO_STATS (country, interval);

=cut

=head1 CLASS ATTRIBUTES

=head2 schema_definition

Database schema

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        geo => {
            stats => {
                country   => [ varchar => 2 ],
                interval  => [ varchar => 25 ],
                counter   => 'integer',
                -unique   => [ 'country', 'interval' ]
            },
        }
    };
} );

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

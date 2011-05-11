package Mail::Decency::Doorman::Model::LiveStats;

=head1 NAME

Mail::Decency::Doorman::Model::LiveStats - Schema definition for LiveStats

=head1 DESCRIPTION

Implements schema definition for LiveStats

=cut

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
        livestats_doorman => {
            stats => {
                time    => 'integer',
                from    => [ varchar => 255 ],
                to      => [ varchar => 255 ],
                status  => [ varchar => 25 ],
                subject => [ varchar => 255 ],
                -index  => [ 'time' ]
            },
            accumulate => {
                key         => [ varchar => 255 ],
                value       => [ varchar => 500 ],
                period      => [ varchar => 25 ],
                last_update => 'integer',
                -unique     => [ 'key', 'value', 'period' ],
                -index      => [ 'last_update' ]
            },
        },
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

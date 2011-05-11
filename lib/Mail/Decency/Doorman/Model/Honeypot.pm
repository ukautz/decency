package Mail::Decency::Doorman::Model::Honeypot;

=head1 NAME

Mail::Decency::Doorman::Model::Honeypot - Schema definition for Honeypot

=head1 DESCRIPTION

Implements schema definition for Honeypot

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

=head1 DATABASE

    CREATE TABLE honeypot_ips (
        id INTEGER PRIMARY KEY,
        ip varchar( 39 ),
        created INTEGER
    );
    CREATE UNIQUE INDEX honeypot_ips_uk ON honeypot_ips( ip );
    CREATE INDEX honeypot_client_created_idx ON honeypot_ips( created );

=head2 schema_definition : HashRef[Bool]

List of addresses used as honeyport targets

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        honeypot => {
            ips => {
                ip      => [ varchar => 39 ],
                created => 'integer',
                -unique => [ 'ip' ],
                -index  => [ 'created' ]
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

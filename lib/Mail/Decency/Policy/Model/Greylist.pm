package Mail::Decency::Policy::Model::Greylist;

=head1 NAME

Mail::Decency::Policy::Model::Greylist - Schema definition for Greylist

=head1 DESCRIPTION

Implements schema definition for Greylist

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

    -- contains all sender host ips, which are or are to be
    --  whitelisted due to lot's of positives
    CREATE TABLE greylist_ips (
        id INTEGER PRIMARY KEY,
        ip VARCHAR( 39 ),
        counter integer,
        last_seen integer
    );
    CREATE UNIQUE INDEX greylist_ips_uk ON greylist_ips( ip );
    
    -- contains all from_domains, which are or are to be
    --  whitelisted due to lot's of positives
    CREATE TABLE greylist_from_domain (
        id INTEGER PRIMARY KEY,
        from_domain varchar( 255 ),
        counter integer,
        last_seen integer,
        unique_sender BLOB
    );
    CREATE UNIQUE INDEX greylist_from_domain_uk ON greylist_from_domain( from_domain );
    
    -- contains all (sender -> recipient) address pairs which
    --  are used to allow the second send attempt
    CREATE TABLE greylist_sender_recipient (
        id INTEGER PRIMARY KEY,
        from_address varchar( 255 ),
        to_address varchar( 255 ),
        counter integer,
        last_seen integer,
        unique_sender BLOB
    );
    CREATE UNIQUE INDEX greylist_sender_recipient_uk ON greylist_sender_recipient( from_address, to_address );

=head2 schema_definition : HashRef[HashRef]

Database schema

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        greylist => {
            address => {
                from_address => [ varchar => 255 ],
                ip           => [ varchar => 39 ],
                to_address   => [ varchar => 255 ],
                data         => 'integer',
                last_update  => 'integer',
                -unique      => [ 'from_address', 'ip', 'to_address' ],
                -index       => [ 'last_update' ],
            },
            recipient => {
                from_address => [ varchar => 255 ],
                ip           => [ varchar => 39 ],
                to_domain    => [ varchar => 255 ],
                data         => 'integer',
                last_update  => 'integer',
                -unique      => [ 'from_address', 'ip', 'to_domain' ],
                -index       => [ 'last_update' ],
            },
            sender => {
                from_domain => [ varchar => 255 ],
                ip          => [ varchar => 39 ],
                to_domain   => [ varchar => 255 ],
                data        => 'integer',
                last_update => 'integer',
                -unique     => [ 'from_domain', 'ip', 'to_domain' ],
                -index      => [ 'last_update' ],
            }
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

package Mail::Decency::Doorman::Model::CBL;

=head1 NAME

Mail::Decency::Doorman::Model::CBL - Schema definition for CBL

=head1 DESCRIPTION

Implements schema definition for CBL

=cut

use strict;
use warnings;
use Mouse;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 DATABASE

    CREATE TABLE cbl_ips (
        id INTEGER PRIMARY KEY,
        to_domain varchar( 255 ),
        ip varchar( 39 )
    );
    CREATE UNIQUE INDEX cbl_ips_uk ON cbl_ips( to_domain, ip );
    
    CREATE TABLE cbl_domains (
        id INTEGER PRIMARY KEY,
        to_domain varchar( 255 ),
        from_domain varchar( 255 )
    );
    CREATE UNIQUE INDEX cbl_domains_uk ON cbl_domains( to_domain, from_domain );
    
    CREATE TABLE cbl_addresses (
        id INTEGER PRIMARY KEY,
        to_domain varchar( 255 ),
        from_address varchar( 255 )
    );
    CREATE UNIQUE INDEX cbl_addresses_uk ON cbl_addresses( to_domain, from_address );



=head1 CLASS ATTRIBUTES

=head2 schema_definition

Schema for CWL

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        cbl => {
            ips => {
                to_domain => [ varchar => 255 ],
                ip        => [ varchar => 39 ],
                -unique   => [ 'to_domain', 'ip' ],
            },
            domains => {
                to_domain   => [ varchar => 255 ],
                from_domain => [ varchar => 255 ],
                -unique     => [ 'to_domain', 'from_domain' ],
            },
            addresses => {
                to_domain    => [ varchar => 255 ],
                from_address => [ varchar => 255 ],
                -unique      => [ 'to_domain', 'from_address' ],
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

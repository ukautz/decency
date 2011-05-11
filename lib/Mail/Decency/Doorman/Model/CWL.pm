package Mail::Decency::Doorman::Model::CWL;

=head1 NAME

Mail::Decency::Doorman::Model::CWL - Schema definition for CWL

=head1 DESCRIPTION

Implements schema definition for CWL

=cut

use strict;
use warnings;
use Mouse;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 DATABASE

    CREATE TABLE cwl_ips (
        id INTEGER PRIMARY KEY,
        to_domain varchar( 255 ),
        ip varchar( 39 )
    );
    CREATE UNIQUE INDEX cwl_ips_uk ON cwl_ips( to_domain, ip );
    
    CREATE TABLE cwl_domains (
        id INTEGER PRIMARY KEY,
        to_domain varchar( 255 ),
        from_domain varchar( 255 )
    );
    CREATE UNIQUE INDEX cwl_domains_uk ON cwl_domains( to_domain, from_domain );
    
    CREATE TABLE cwl_addresses (
        id INTEGER PRIMARY KEY,
        to_domain varchar( 255 ),
        from_address varchar( 255 )
    );
    CREATE UNIQUE INDEX cwl_addresses_uk ON cwl_addresses( to_domain, from_address );

=cut

=head1 CLASS ATTRIBUTES

=head2 schema_definition

Schema for CWL

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        cwl => {
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

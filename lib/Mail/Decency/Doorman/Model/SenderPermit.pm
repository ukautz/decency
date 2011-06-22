package Mail::Decency::Doorman::Model::SenderPermit;

=head1 NAME

Mail::Decency::Doorman::Model::SenderPermit - Schema definition for SenderPermit

=head1 DESCRIPTION

Implements schema definition for SenderPermit

=cut

use strict;
use warnings;
use Mouse;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 DATABASE

    CREATE TABLE sender_permit (
        id INTEGER PRIMARY KEY,
        from_domain VARCHAR(255),
        to_domain VARCHAR(255),
        fingerprint VARCHAR(160),
        subject VARCHAR(255),
        ip VARCHAR(39)
    );
    CREATE UNIQUE INDEX sender_permit_uk ON sender_permit( from_domain, to_domain, fingerprint, subject, ip );

=cut

=head1 CLASS ATTRIBUTES

=head2 schema_definition

Database schema

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        sender => {
            permit => {
                from_domain => [ varchar => 255 ],
                to_domain   => [ varchar => 255 ],
                fingerprint => [ varchar => 160 ],
                subject     => [ varchar => 255 ],
                ip          => [ varchar => 39 ],
                -unique     => [ 'from_domain', 'to_domain', 'fingerprint', 'subject', 'ip' ]
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

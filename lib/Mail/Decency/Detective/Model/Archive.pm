package Mail::Decency::Detective::Model::Archive;

=head1 NAME

Mail::Decency::Doorman::Model::Archive - Schema definition for Archive Index

=head1 DESCRIPTION

Implements schema definition for Archive Index

=cut

use strict;
use warnings;
use Mouse;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 DATABASE

    CREATE TABLE archive_index (
        id INTEGER PRIMARY KEY,
        subject varchar( 255 ),
        from varchar( 255 ),
        to varchar( 255 ),
        created integer,
        search text,
        filename text
    );
    CREATE INDEX archive_index_subject ON archive_index( subject );
    CREATE INDEX archive_index_from ON archive_index( from );
    CREATE INDEX archive_index_to ON archive_index( to );
    CREATE INDEX archive_index_created ON archive_index( created );

=head1 CLASS ATTRIBUTES

=head2 schema_definition

Schema for Archive 

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        archive => {
            index => {
                subject     => [ varchar => 255 ],
                from_domain => [ varchar => 255 ],
                from_prefix => [ varchar => 255 ],
                to_domain   => [ varchar => 255 ],
                to_prefix   => [ varchar => 255 ],
                created     => 'int',
                search      => 'text',
                filename    => 'text',
                md5         => [ varchar => 32 ],
                -index      => [
                    [ 'created' ],
                    [ 'subject' ],
                    [ 'from_domain', 'from_prefix' ],
                    [ 'to_domain', 'to_prefix' ]
                ]
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

package Mail::Decency::Policy::Model::Throttle;

=head1 NAME

Mail::Decency::Policy::Model::Throttle - Schema definition for Throttle

=head1 DESCRIPTION

Implements schema definition for Throttle

=cut

use strict;
use warnings;
use Mouse;
use mro 'c3';

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 DATABASE

    CREATE TABLE throttle_client_address (
        id INTEGER PRIMARY KEY,
        client_address VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER,
        account VARCHAR( 25 )
    );
    CREATE UNIQUE INDEX throttle_client_address_uk ON throttle_client_address( client_address, interval );
    
    CREATE TABLE throttle_sender_domain (
        id INTEGER PRIMARY KEY,
        sender_domain VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER,
        account VARCHAR( 25 )
    );
    CREATE UNIQUE INDEX throttle_sender_domain_uk ON throttle_sender_domain( sender_domain, interval );
    
    CREATE TABLE throttle_sender_address(
        id INTEGER PRIMARY KEY,
        sender_address VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER,
        account VARCHAR( 25 )
    );
    CREATE UNIQUE INDEX throttle_sender_address_uk ON throttle_sender_address( sender_address, interval );
    
    CREATE TABLE throttle_sasl_username(
        id INTEGER PRIMARY KEY,
        sasl_username VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER,
        account VARCHAR( 25 )
    );
    CREATE UNIQUE INDEX throttle_sasl_username_uk ON throttle_sasl_username( sasl_username, interval );
    
    CREATE TABLE throttle_recipient_domain(
        id INTEGER PRIMARY KEY,
        recipient_domain VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER,
        account VARCHAR( 25 )
    );
    CREATE UNIQUE INDEX throttle_recipient_domain_uk ON throttle_recipient_domain( recipient_domain, interval );
    
    CREATE TABLE throttle_recipient_address(
        id INTEGER PRIMARY KEY,
        recipient_address VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER,
        account VARCHAR( 25 )
    );
    CREATE UNIQUE INDEX throttle_recipient_address_uk ON throttle_recipient_address( recipient_address, interval );
    
    CREATE TABLE throttle_account(
        id INTEGER PRIMARY KEY,
        account VARCHAR( 255 ),
        interval INTEGER,
        maximum INTEGER
    );
    CREATE UNIQUE INDEX throttle_account_uk ON throttle_account( account, interval );

=cut

=head1 CLASS ATTRIBUTES

=head2 schema_definition

Database schema

=cut

has schema_definition => ( is => 'ro', isa => 'HashRef[HashRef]', default => sub {
    {
        throttle => {
            client_address => {
                client_address => [ varchar => 39 ],
                interval       => 'integer',
                maximum        => 'integer',
                account        => [ varchar => 100 ],
                -unique        => [ 'client_address', 'interval' ]
            },
            sender_domain => {
                sender_domain => [ varchar => 255 ],
                interval      => 'integer',
                maximum       => 'integer',
                account       => [ varchar => 100 ],
                -unique       => [ 'sender_domain', 'interval' ]
            },
            sender_address => {
                sender_address => [ varchar => 255 ],
                interval       => 'integer',
                maximum        => 'integer',
                account        => [ varchar => 100 ],
                -unique        => [ 'sender_address', 'interval' ]
            },
            sasl_username => {
                sasl_username => [ varchar => 255 ],
                interval      => 'integer',
                maximum       => 'integer',
                account       => [ varchar => 100 ],
                -unique       => [ 'sasl_username', 'interval' ]
            },
            recipient_domain => {
                recipient_domain => [ varchar => 255 ],
                interval         => 'integer',
                maximum          => 'integer',
                account          => [ varchar => 100 ],
                -unique          => [ 'recipient_domain', 'interval' ]
            },
            recipient_address => {
                recipient_address => [ varchar => 255 ],
                interval          => 'integer',
                maximum           => 'integer',
                account           => [ varchar => 100 ],
                -unique           => [ 'recipient_address', 'interval' ]
            },
            account => {
                account  => [ varchar => 100 ],
                interval => 'integer',
                maximum  => 'integer',
                account  => [ varchar => 100 ],
                -unique  => [ 'account', 'interval' ]
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

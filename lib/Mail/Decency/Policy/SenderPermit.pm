package Mail::Decency::Policy::SenderPermit;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Policy::Core
    Mail::Decency::Policy::Model::SenderPermit
/;
with qw/
    Mail::Decency::Core::Meta::Database
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );



=head1 NAME

Mail::Decency::Policy::SenderPermit

=head1 CONFIG

    ---
    
    disable: 0
    disable_strict_channel: 0
    disable_loose_channel: 0
    disable_strict_relaying: 0
    disable_loose_ip_relaying: 0
    disable_loose_cert_relaying: 0


=head1 DESCRIPTION

Gives senders based on (IP|Certificate) + sender domain send permissions (OK)

This module has no extensive configuration options. However, the database entries can
have 5 different forms:

=head2 DATABASE ENTRIES

=head3 strict channel

In this case, the permissions are defined by a sender domain and a recipient domain. Also the sender can only send from a distinct IP and has to provide a certain certificate with a determined subject and fingerprint

Use Case: External sender, which delivers mail via SMTPS to a certain recipient (eg automated report script)

Example:

    from_domain: sender.tld
    to_domain: recipient.tld
    fingerprint: C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:04
    subject: solaris9.porcupine.org
    ip: 123.123.123.123

=head3 loose channel

The sender (determined by IP) is allowed to send from a certain sender domain to a certain sender domain. No certificate required.

Use Case: LAN or VPN sender, which delivers mail to a certain recipient (eg automated report script)

Example:

    from_domain: sender.tld
    to_domain: recipient.tld
    fingerprint: *
    subject: *
    ip: 123.123.123.123

=head3 strict relaying

Same as strict channel, but the sender can target any domain

Use Case: Best relaying mode, if the sender has a static IP and delivers mail via SMTPS

Example:

    from_domain: sender.tld
    to_domain: *
    fingerprint: C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:04
    subject: solaris9.porcupine.org
    ip: 123.123.123.123

=head3 loose ip based relaying

The sender can target any recipient and is identified by his IP only

Use Case: The sender has a static IP and you trust your network. He can relay any mail. Warning: IP forging is possible.. however, if the sender is in the LAN or in a VPN..

Example:

    from_domain: sender.tld
    to_domain: *
    fingerprint: *
    subject: *
    ip: 123.123.123.123

=head3 loose cert based relaying

The sender can target any recipient and is identified by his IP only

Use Case: The sender has a dynamic IP but always provides the same cert and want's to relay mails via your smtp server.

Example:

    from_domain: sender.tld
    to_domain: *
    fingerprint: C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:04
    subject: solaris9.porcupine.org
    ip: *


=head1 ATTRIBUTES

=head2 _channel_methods

=cut

has _channel_methods => ( isa => 'ArrayRef', is => 'rw', default => sub { [] } );

=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    my %channel = (
        strict_channel => sub {
            my ( $session ) = @_;
            {
                from_domain => $session->from_domain,
                to_domain   => $session->to_domain,
                fingerprint => $session->attrs->{ ccert_fingerprint },
                subject     => $session->attrs->{ ccert_subject },
                ip          => $session->ip,
            }
        },
        
        loose_channel => sub {
            my ( $session ) = @_;
            {
                from_domain => $session->from_domain,
                to_domain   => $session->to_domain,
                fingerprint => '*',
                subject     => '*',
                ip          => $session->ip,
            }
        },
        
        strict_relaying => sub {
            my ( $session ) = @_;
            {
                from_domain => $session->from_domain,
                to_domain   => '*',
                fingerprint => $session->attrs->{ ccert_fingerprint },
                subject     => $session->attrs->{ ccert_subject },
                ip          => $session->ip,
            }
        },
        
        loose_ip_relaying => sub {
            my ( $session ) = @_;
            {
                from_domain => $session->from_domain,
                to_domain   => '*',
                fingerprint => '*',
                subject     => '*',
                ip          => $session->ip,
            }
        },
        
        loose_cert_relaying => sub {
            my ( $session ) = @_;
            {
                from_domain => $session->from_domain,
                to_domain   => '*',
                fingerprint => $session->attrs->{ ccert_fingerprint },
                subject     => $session->attrs->{ ccert_subject },
                ip          => '*',
            }
        }
    );
    
    my @channels = ();
    foreach my $channel( qw/
        strict_channel
        loose_channel
        strict_relaying
        loose_ip_relaying
        loose_cert_relaying
    / ) {
        next if $self->config->{ "disabled_$channel" };
        push @channels, [ $channel, $channel{ $channel } ];
    }
    $self->_channel_methods( \@channels );
}



=head2 handle

Either build stats per country or score with negative or positve weight per country or do both

=cut

sub handle {
    my ( $self ) = @_;
    
    # init vars
    my $db      = $self->database;
    my $session = $self->session;
    
    # get cache name
    my $cache_name = join( ':',
        $session->ip,
        $session->attrs->{ ccert_fingerprint },
        $session->attrs->{ ccert_subject },
        $session->from_domain,
        $session->to_domain,
    );
    
    # check in cache
    my $cached = $self->cache->get( $cache_name );
    
    # return cache, if found
    return $self->go_final_state( $cached ) if $cached;
    
    # build db checks
    my @check = map {
        [ $_->[0], $_->[1]->( $session ) ];
    } @{ $self->_channel_methods };
    
    # search in database
    foreach my $ref( @check ) {
        my ( $name, $check_ref ) = @$ref;
        my $ref = $db->get( sender => permit => $check_ref );
        
        # found permission.. cache and return OK
        if ( $ref && defined $ref->{ ip } ) {
            $self->cache->set( $cache_name => 'OK' );
            $self->logger->debug2( "FOUND on permission list $name : '$cache_name'" );
            return $self->go_final_state( 'OK' );
        }
        else {
            $self->logger->debug3( "Not on $name : '$cache_name'" );
        }
    }
    
    $self->logger->debug2( "Not found on permission list: '$cache_name'" );
    
    # nothing found -> save to cache 
    $self->cache->set( $cache_name => 'DUNNO' );
    return ;
}





=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

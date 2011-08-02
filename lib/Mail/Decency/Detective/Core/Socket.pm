package Mail::Decency::Detective::Core::Socket;

use Mouse;
with qw/
    Mail::Decency::Detective::Core
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Mail::Decency::Detective::Core::Constants;
use IO::Socket;
use IO::Socket::UNIX;
use IO::Socket::INET;
use Net::SMTP;

=head1 NAME

Mail::Decency::Detective::Core::Cmd

=head1 DESCRIPTION

@@ NOT RELEASED @@

Base class for all command line filters. Including spam filter such as DSPAM and so on

=head1 CLASS ATTRIBUTES


=head2 socket : IO::Socket

Socket for connection

=cut

has socket => ( is => 'rw', isa => 'IO::Socket' );
has port   => ( is => 'rw', isa => 'Int' );
has host   => ( is => 'rw', isa => 'Str', predicate => 'has_host' );
has path   => ( is => 'rw', isa => 'Str', predicate => 'has_path' );
has use_smtp => ( is => 'rw', isa => 'Bool', default => 0 );



=head1 METHODS


=head2 init

=cut

before init => sub {
    my ( $self ) = @_;
    
    my $max_tries = 10;
    while ( ! $self->socket ) {
        if ( $self->config->{ host } ) {
            $self->host( $self->config->{ host } );
            DD::cop_it ref( $self ).": Require port in config if using host\n"
                unless $self->config->{ port };
            $self->port( $self->config->{ port } );
            
            if ( $self->use_smtp ) {
                my $address = $self->host. ':'. $self->port;
                my $smtp = Net::SMTP->new(
                    $address,
                    Debug    => 1,
                    Hello    => 'decency',
                    Timeout  => $self->config->{ timeout } || 30
                ) or DD::cop_it "Ooops: $address $!\n";
                $self->socket( $smtp );
            }
            else {
                $self->socket( IO::Socket::INET->new(
                    PeerHost => $self->host,
                    PeerPort => $self->port,
                    Proto    => 'tcp',
                    Timeout  => $self->config->{ timeout } || 30
                ) );
            }
        }
        elsif ( $self->config->{ path } ) {
            $self->path( $self->config->{ path } );
            my $socket = IO::Socket::UNIX->new(
                Peer     => $self->path,
            ) or DD::cop_it "Cannot open socket: $!\n";
            $self->socket( $socket );
        }
        else {
            DD::cop_it ref( $self ). ": Require either host and port OR path\n";
        }
        last if $max_tries-- <= 0;
        $self->logger->debug0( "Wait for socket" );
        sleep 1;
    }
    DD::cop_it "Gaving up on waiting for connection\n"
        unless $self->socket;
};


=head2 handle

Communication wit socket (SMTP TCP, Unix Socket)

=cut


sub handle {
    my ( $self ) = @_;
    
    # pipe file throught command
    my ( $status, $result );
    if ( $self->use_smtp ) {
        ( $status, $result ) = $self->smtp_filter;
    }
    else {
        ( $status, $result ) = $self->socket_filter;
    }
    
    # return nwo if filter does not handle the file
    return $status unless $status eq DETECTIVE_FILTER_OK;
    
    # chomp lines
    1 while chomp $result;
    
    # handle result by the actual filter module
    return $self->handle_filter_result( $result );
}


=head2 smtp_filter

Pipes mail content through command line program and caches result

=cut

sub smtp_filter {
    my ( $self ) = @_;
    
    # send ello to socket
    $self->socket->hello( 'localhost' );
    $self->socket->mail( $self->from );
    $self->socket->to( $self->to );
    $self->socket->data;
    
    # open input file for read
    my $fh = $self->open_file( '<', $self->file );
    while ( my $l = <$fh> ) {
        chomp $l;
        $self->socket->datasend( $l . CRLF );
    }
    close $fh;
    $self->socket->dataend;
    
    # retreive response
    my @response = ();
    push @response, $self->socket->message;
    
    # bye..
    $self->socket->quit;
    push @response, $self->socket->message;
    
    # return result
    return ( DETECTIVE_FILTER_OK, join( " ", @response ) );
}


=head2 socket_filter

Pipes mail content through command line program and caches result

=cut

sub socket_filter {
    my ( $self ) = @_;
    
    # print to socket
    my $fh = $self->open_file( '<', $self->file );
    while ( my $l = <$fh> ) {
        $self->socket->write( $l );
    }
    my $buf;
    do {
        $self->socket->read( $buf, 1024 );
        print "READ '$buf'\n";
    } while $buf
    
    return $buf;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

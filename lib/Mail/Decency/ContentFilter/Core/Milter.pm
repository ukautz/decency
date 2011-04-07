package Mail::Decency::ContentFilter::Core::Milter;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.1.9_1" );

use Mail::Decency::ContentFilter::Core::Constants;
use Net::Milter;

=head1 NAME

Mail::Decency::ContentFilter::Core::Cmd

=head1 DESCRIPTION

@@ NOT RELEASED @@

Base class for all command line filters. Including spam filter such as DSPAM and so on

=head1 CLASS ATTRIBUTES

=cut

has milter  => ( is => 'rw', isa => 'Net::Milter' );
has port    => ( is => 'rw', isa => 'Int' );
has host    => ( is => 'rw', isa => 'Str', predicate => 'has_host' );
has path    => ( is => 'rw', isa => 'Str', predicate => 'has_path' );


=head1 METHODS


=head2 init

=cut

before init => sub {
    my ( $self ) = @_;
    
    my $max_tries = 10;
    my $milter = Net::Milter->new;
    
    # try get socket
    while ( ! $self->milter ) {
        
        # using host + port
        if ( $self->config->{ host } ) {
            $self->host( $self->config->{ host } );
            die ref( $self ).": Require port in config if using host\n"
                unless $self->config->{ port };
            $self->port( $self->config->{ port } );
            $milter->open( $self->host, $self->port, 'tcp' );
            
            # set timeout
            $milter->{ socket }->timeout( $self->config->{ timeout } || 5 )
                if $milter->{ socket };
        }
        
        # using path
        elsif ( $self->config->{ path } ) {
            $self->path( $self->config->{ path } );
            $milter->open( $self->path, $self->config->{ timeout } || 30, 'unix' );
        }
        
        # what do you use ?
        else {
            die ref( $self ). ": Require either host and port OR path\n";
        }
        
        # set milter if socket ok
        $self->milter( $milter )
            if $milter->{ socket };
        
        # break on last trye
        last if $max_tries-- <= 0;
        
        # still waiting some..
        $self->logger->debug0( "Wait for socket" );
        sleep 1;
    }
    
    # check wheter all ok
    die "Gaving up on waiting for connection\n"
        unless $self->milter;
    
    return;
};


=head2 handle

Default handling for any content filter is getting info about the to be filterd file

=cut


sub handle {
    my ( $self ) = @_;
    
    print "HANDLE MILTER\n";
    
    # get filter proto from milter (check wheter up)
    print "PRE CONNECTION\n";
    my ( $version, @x ) = $self->milter->protocol_negotiation(
        # SMFIF_ADDHDRS   => 1,
        # SMFIF_ADDRCPT   => 1,
        # SMFIF_DELRCPT   => 1,
        # SMFIF_CHGHDRS   => 1,
        # SMFIF_CHGBODY   => 1,
        # SMFIP_NOCONNECT => 1,
        # SMFIP_NOHELO    => 1,
        # SMFIP_NOMAIL    => 1,
        # SMFIP_NORCPT    => 1,
        # SMFIP_NOBODY    => 0,
        # SMFIP_NOHDRS    => 1,
        # SMFIP_NOEOH     => 1,
        # SMFIF_ADDHDRS   => 0,
        # SMFIF_CHGBODY   => 1,
        # SMFIP_NOEHO     => 1,
        # SMFIP_NOCONNECT => 1

    );
    print Dumper( [ $version => \@x ] );
    die "Version could not be determined\n" unless $version;
    
    # get mime for sending headers and such
    my $mime = $self->mime;
    
    my @res;
    
    
    # send connect stuff
    #@res = $self->milter->send_connect( 
    
    print "BEFORE HEADERS\n";
    # send header
    my $header = $mime->head;
    # push @res, $self->milter->send_mail_from( $self->from );
    # print "AFTER MAIL FROM \n";
    # print Dumper( \@res );
    
    # push @res, $self->milter->send_rcpt_to( $self->to );
    # print "AFTER RCPT TO\n";
    # print Dumper( \@res );
    
    foreach my $tag( $header->tags ) {
        print "SEND ". $tag. " => ". $header->get( $tag ). "\n";
        my ( $ref ) = $self->milter->send_header( $tag => $header->get( $tag ) );
        print "AFTER HEADER $tag\n";
        print Dumper( $ref );
        die "Ooops .. \n" if $ref->{ action } eq 'reject';
    }
    
    push @res, $self->milter->send_end_headers;
    print "AFTER HEADER FINISH\n";
    print Dumper( \@res );
    
    # send body
    print "BEFORE SEND BODY\n";
    push @res, $self->milter->send_body( $mime->stringify_body );
    print Dumper( \@res );
    
    # send end
    print "BEFORE END BODY\n";
    push @res, $self->milter->send_end_body();
    
    push @res, $self->milter->send_quit();
    
    print "ALL OVER\n";
    
    
    my $result;
    
    # handle result by the actual filter module
    return $self->handle_filter_result( $result );
}


=head2 smtp_filter

Pipes mail content through command line program and caches result

=cut

sub smtp_filter {
    my ( $self ) = @_;
    
    $self->socket->hello( 'localhost' );
    $self->socket->mail( $self->from );
    $self->socket->to( $self->to );
    $self->socket->data;
    
    my $fh = $self->open_file( '<', $self->file );
    while ( my $l = <$fh> ) {
        chomp $l;
        $self->socket->datasend( $l . CRLF );
    }
    close $fh;
    $self->socket->dataend;
    my @response = ();
    push @response, $self->socket->message;
    $self->socket->quit;
    push @response, $self->socket->message;
    use Data::Dumper; print Dumper \@response;
    return ( CF_FILTER_OK, join( " ", @response ) );
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
    
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

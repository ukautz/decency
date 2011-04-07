package Mail::Decency::Core::POEForking::Postfix;

use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.1.5" );

use Mail::Decency::Core::POEForking;
use base qw/
    Mail::Decency::Core::POEForking
/;

use POE qw/
    Wheel::ReadWrite
/;

use Scalar::Util qw/ weaken /;
use Socket qw/ inet_ntoa /;
use Data::Dumper;

=head1 NAME

Mail::Decency::Core::POEForking::Postfix

=head1 DESCRIPTION

Postfix instance to be used with POEForking

=head1 METHODS

=head2 create_handler

Called by the forking/treading parent server

=cut

sub create_handler {
    my $class = shift;
    my ( $heap, $session, $socket, $peer_addr, $peer_port )
        = @_[ HEAP, SESSION, ARG0, ARG1, ARG2 ];
    
    POE::Session->create(
        inline_states => {
            _start        => \&postfix_start,
            _stop         => \&postfix_stop,
            postfix_input => \&postfix_input,
            postfix_flush => \&postfix_flush,
            postfix_error => \&postfix_error,
            good_night    => \&postfix_stop,
            #_parent       => sub { 0 },
            # _default           => sub {
            #     my ( $heap, $event, $args ) = @_[ HEAP, ARG0, ARG1 ];
            #     $heap->{ logger }->error( "** UNKNOWN EVENT $event, $args" );
            # }
        },
        heap => {
            decency   => $heap->{ decency },
            logger    => $heap->{ decency }->logger,
            conf      => $heap->{ conf },
            server    => $heap->{ server },
            parent    => $session,
            socket    => $socket,
            peer_addr => inet_ntoa( $peer_addr ),
            peer_port => $peer_port,
        }
   );
}


=head2 postfix_start

Start connection from postfix

=cut


sub postfix_start {
    return client_start( postfix =>
        POE::Filter::Postfix::Plain->new(),
        @_[ KERNEL, SESSION, HEAP ]
    );
}


=head2 postfix_input

Incoming data from postfix

=cut

sub postfix_input {
    my ( $heap, $attr ) = @_[ HEAP, ARG0 ]; # ARG0 = OUTPUT, ARG1 = WID
    my $answer = eval { $heap->{ decency }->get_handlers()->( $heap->{ server }, $attr ) };
    if ( $@ ) {
        $heap->{ logger }->error( "Error in handling: $@" );
        $heap->{ client }->put( { action => '450 Temporary problem' } );
    }
    else {
        $heap->{ client }->put( $answer );
    }
    
    $heap->{ finished } = 1;
    $heap->{ logger }->debug3( "Disconnecting FINISHED (". join( ' / ', map {
        sprintf( '%s: "%s"', $_, $answer->{ $_ } );
    } sort keys %$answer ). ")" );
}


=head2 postfix_stop

Stop connection.. called when WE finish the connection (eg SIG TERM)

=cut

sub postfix_stop {
    return cleanup_stop( @_[ HEAP, SESSION ] );
    # $heap->{ logger }->debug3( "Disconnecting from postfix" );
    # eval { close $heap->{ socket } }
    #     if $heap->{ socket };
    # $heap->{ logger }->error( "Could not close socket: $@" ) if $@;
    
    # foreach my $conn( qw/ socket server / ) { # server
    #     eval { delete $heap->{ $conn } } if defined $heap->{ $conn };
    #     $heap->{ logger }->error( "Could not remove $conn from list after postfix stop: $@" )
    #         if $@;
    # }
    
    # return;
}




=head2 postfix_flush

Flush connection .. ignore this

=cut

sub postfix_flush {
    return cleanup_client( @_[ HEAP, SESSION ], "FLUSH" );
}


=head2 postfix_error

Handles connection erros from postfix .. as well as disconnects (not flush)

=cut

sub postfix_error {
    # ARG 0 = operation
    # ARG 1 = errnum
    # ARG 2 = errstr
    # ARG 3 = WID
    return handle_conn_error( @_[ HEAP, SESSION, ARG0..ARG3 ] );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

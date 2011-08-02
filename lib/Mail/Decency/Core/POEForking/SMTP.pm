package Mail::Decency::Core::POEForking::SMTP;

use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.1.5" );

use feature 'switch';

use Mail::Decency::Core::POEForking;
use base qw/
    Mail::Decency::Core::POEForking
/;

use POE qw/
    Wheel::ReadWrite
/;

use File::Temp qw/ tempfile /;
use Mail::Decency::Detective::Core::Constants;
use Mail::Decency::Core::POEFilterSMTP;
use Socket qw/ inet_ntoa /;
use Data::Dumper;

=head1 NAME

Mail::Decency::Core::POEForking::SMTP

=head1 DESCRIPTION

SMTP Server for the Detective

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
            _start     => \&smtp_start,
            _stop      => \&smtp_stop,
            smtp_input => \&smtp_input,
            smtp_flush => \&smtp_flush,
            smtp_error => \&smtp_error,
            good_night => \&smtp_stop,
            _parent    => sub { 0 },
            # _default        => sub {
            #     my ($event, $args) = @_[ARG0, ARG1];
            #     warn "** SMTP: UNKNOWN EVENT $event, $args\n";
            # }
        },
        heap => {
            decency   => $heap->{ decency },
            conf      => $heap->{ conf },
            logger    => $heap->{ decency }->logger,
            args      => $heap->{ args },
            parent    => $session,
            socket    => $socket,
            peer_addr => inet_ntoa( $peer_addr ),
            peer_port => $peer_port,
        }
    );
}


=head2 smtp_start

Start connection from mail server

=cut

sub smtp_start {
    my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];
    
    # start
    client_start( smtp =>
        Mail::Decency::Core::POEFilterSMTP->new(),
        @_[ KERNEL, SESSION, HEAP ]
    );
    
    # # tell the parent session we are here
    # $kernel->post( $heap->{ parent }, "new_client_session", $session );
    
    # # start new r/w on the socket
    # $heap->{ client } = POE::Wheel::ReadWrite->new(
    #     Handle       => $heap->{ socket },
    #     Filter       => Mail::Decency::Core::POEFilterSMTP->new(),
    #     InputEvent   => "smtp_input",
    #     ErrorEvent   => "smtp_error",
    #     FlushedEvent => "smtp_flush",
    # );
    
    # say hello
    $heap->{ client }->put( 220 => "Welcome" );
}


=head2 smtp_input

Handling input

=cut

sub smtp_input {
    my ( $kernel, $heap, $session, $input ) = @_[ KERNEL, HEAP, SESSION, ARG0 ];
    return unless $input && ref( $input ) eq 'ARRAY';
    
    # first pass parse
    my ( $cmd, $arg, $line ) = @$input;
    $arg ||= "";
    
    # being in the DATA part:
    if ( $heap->{ in_data } ) {
        
        # last final "." -> end of DATA
        if ( $cmd eq '.' ) {
            
            # close file handle
            close delete $heap->{ mime_fh };
            
            # unmark data
            $heap->{ in_data } = 0;
            
            # handle input data with decency
            my ( $ok, $reject_message );
            eval {
                ( $ok, $reject_message ) = $heap->{ decency }->handle_safe( {
                    file => delete $heap->{ mime_file },
                    from => delete $heap->{ mail_from },
                    to   => delete $heap->{ rcpt_to },
                } );
            };
            if ( $@ ) {
                $heap->{ logger }->error( "Error in handler: $@" );
                $heap->{ client }->put( 450 => "Temporary problem" );
            }
            else {
                
                # send bye to client
                if ( $ok ) {
                    $heap->{ logger }->debug3( "Send 250 to mail server, mail accepted" );
                    $heap->{ client }->put( 250 => 'Bye ' );
                }
                else {
                    $heap->{ logger }->debug3( "Send 554 to mail server, mail bounced" );
                    $heap->{ client }->put( 554 => $reject_message || "Rejected" );
                }
            }
            
            # close connection to mail server
            delete $heap->{ $_ }
                for qw/ mail_from rcpt_to mime_fh mime_file /; # client socket
            
            
            # back to begin
            $heap->{ in_data } = 0;
        }
        
        # collecting DATA
        else {
            my $fh = $heap->{ mime_fh };
            print $fh $line;
        }
    }
    
    # not in DATA -> catch SMTP commands
    else {
        
        $ENV{ DEBUG_SMTP } && warn "> $cmd | $arg\n"; 
        
        # MAIL FROM commmand -> rewrite for handling
        if ( $cmd eq 'MAIL' && $arg =~ /^FROM:\s*(?:<([^>]*?)>|(.*?))\s*$/ ) {
            $cmd = 'MAIL_FROM';
            $heap->{ mail_from } = $arg = $1 || $2 || "";
        }
        
        # RCPT TO commmand -> rewrite for handling
        elsif ( $cmd eq 'RCPT' && $arg =~ /^TO:\s*(?:<([^>]*?)>|(.*?))\s*$/ ) {
            $cmd = 'RCPT_TO';
            $heap->{ rcpt_to } = $arg = $1 || $2;
        }
        
        # DATA commmand -> init data input
        elsif ( $cmd eq 'DATA' ) {
            
            # not heaving from and to ? not good -> bye to client
            unless ( $heap->{ rcpt_to } ) {
                
                # clear heap
                delete $heap->{ $_ } for qw/ mail_from /;
                
                # send bye, close client
                $heap->{ client }->put( 221 => 'Require RCPT TO' );
                
                return;
            }
            
            # mark being in data
            $heap->{ in_data } ++;
            
            # new temp file in spool dir
            my ( $th, $tn ) = tempfile( $heap->{ args }->{ temp_mask }, UNLINK => 0 );
            $heap->{ mime_fh }   = $th;
            $heap->{ mime_file } = $tn;
        }
        
        # RSET .. not out fault ;)
        elsif ( $cmd eq 'RSET' ) {
            $heap->{ in_data } = 0;
            close delete $heap->{ mime_fh }
                if $heap->{ mime_fh };
            delete $heap->{ $_ } for qw/ mime_file rcpt_to mail_from /; 
        }
        
        
        smtp_response( $heap, $session, $cmd, $line );
    }
}


=head2 smtp_stop

Stop connection, good bye

=cut

sub smtp_stop {
    return cleanup_stop( @_[ HEAP, SESSION ] );
}



=head2 smtp_flush

=cut

sub smtp_flush {
    return cleanup_client( @_[ HEAP, SESSION ], "FLUSH", 1 );
}



=head2 smtp_response

Handle a SMTP input (eg RCPT TO)

=cut

sub smtp_response {
    my ( $heap, $session, $cmd, $line ) = @_;
    
    given ( $cmd ) {
        when ( "EHLO" ) {
            $heap->{ client }->put( 250 => 'XFORWARD NAME ADDR PROTO HELO', 'OK' );
        }
        when ( "HELO" ) {
            $heap->{ client }->put( 250 => 'XFORWARD NAME ADDR PROTO HELO', 'OK' );
        }
        when ( "MAIL_FROM" ) {
            $heap->{ client }->put( 250 => 'OK' );
        }
        when ( "RCPT_TO" ) {
            $heap->{ client }->put( 250 => 'OK' );
        }
        when ( "DATA" ) {
            $heap->{ client }->put( 354 => 'End with "." on a line by itself' );
        }
        when ( "QUIT" ) {
            $heap->{ client }->put( 221 => 'Thanks for the fish' );
            $heap->{ finished } ++;
        }
        when ( "RSET" ) {
            $heap->{ client }->put( 250 => 'It\'s not my fault!' );
            $heap->{ finished } ++;
        }
        when ( "XFORWARD" ) {
            $heap->{ client }->put( 250 => 'Nice, gimme more' );
            DD::dbg "SMTP-FORWARD> Got forward '$line'";
            $heap->{ finished } ++;
        }
        default {
            $heap->{ client }->put( 502 => 'This is not your mail server' );
        }
    }
}



=head2 smtp_error

Called uppon client error .. eg sudden disconnect

=cut

sub smtp_error {
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

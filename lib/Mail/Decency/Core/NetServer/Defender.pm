package Mail::Decency::Core::NetServer::Defender;

=head1 NAME

Mail::Decency::Core::NetServer::Defender

=head1 DESCRIPTION

Pre-Queue SMTP Server for Defender

=cut

use strict;
use warnings;
use base qw/ Mail::Decency::Core::NetServer /;
use Data::Dumper;
use File::Temp qw/ tempfile /;
use File::Copy qw/ copy /;

use constant ENDL => "\r\n";


=head1

=head1 METHODS

=head1 defender

=cut

sub defender {
    shift->{ server }->{ defender };
}

=head1 detective

=cut

sub detective {
    my ( $self ) = @_;
    $self->{ server }->{ defender }->has_detective
        ? $self->{ server }->{ defender }->detective
        : undef;
}

=head1 doorman

=cut

sub doorman {
    my ( $self ) = @_;
    $self->{ server }->{ defender }->has_doorman
        ? $self->{ server }->{ defender }->doorman
        : undef;
}


=head2 write_client $$$

Write to client

    write_client( $client, $cmd, \@lines );

=cut

sub write_client($$$) {
    my ( $client, $cmd, $lines_ref ) = @_;
    my @lines = ref( $lines_ref ) ? @$lines_ref : ( $lines_ref );
    my $last_line = pop @lines;
    foreach my $line( @lines ) {
        $ENV{ SMTP_DEBUG } && warn "OUT> $cmd-$line\n";
        print $client "$cmd-$line". ENDL;
    }
    $ENV{ SMTP_DEBUG } && warn "OUT> $cmd $last_line\n";
    print $client "$cmd $last_line". ENDL;
}

=head2 reset_mail $

Clear / close / remove file handle

=cut

sub reset_mail($) {
    my $mail_ref = shift;
    close delete $mail_ref->{ mime_fh }
        if ( defined $mail_ref->{ mime_fh } );
    if ( my $file = delete $mail_ref->{ mime_file } ) {
        unlink( $file ) if -f $file;
    }
    delete $mail_ref->{ $_ } for keys %$mail_ref;
}

=head2 child_init_hook

Setup servers on init

=cut

sub child_init_hook {
    my ( $self ) = @_;
    $self->defender->setup();
}

=head2 process_request

Handle incoming SMTP request request

=cut

sub process_request {
    my ( $self ) = @_;
    my $client = $self->{ server }->{ client };
    
    write_client $client, 220, 'Welcome';
    my $next = 'helo';
    my %mail;
    
    
    my %attrib;
    while( my $line = <$client> ) {
        
        my ( $cmd, $data ) = split( ' ', $line, 2 );
        $data =~ s/\r\n$//;
        $cmd = uc( $cmd );
        
        $ENV{ SMTP_DEBUG } && warn "IN < '$cmd $data'\n";
        
        # got forwarded envelope data
        if ( $cmd eq 'XFORWARD' ) {
            my %args = map {
                my ( $k, $v ) = /^([A-Z]+)=(.*?)$/;
                ( lc( $k ) => $v );
            } grep {
                /^[A-Z]+=/
            } split( / /, $data );
            $mail{ "client_$_" } = $args{ $_ }
                for keys %args;
        }
        
        # HELO / EHLO
        elsif ( ( $next eq 'helo' || $next eq 'helo_or_quit' ) && $cmd =~ /^(?:HE|EH)LO$/ ) {
            $next = 'from';
            $mail{ helo } = $data;
            write_client $client, 250, 'OK';
        }
        
        # MAIL FROM
        elsif ( $next eq 'from' && $cmd eq 'MAIL' && $data =~ /^from:\s*(.+)$/i ) {
            $mail{ from } = $1;
            if ( $mail{ from } =~ /<(.*?)>/ ) {
                $mail{ from } = $1;
            }
            $mail{ from } =~ s/[\r\n]//gms;
            $next = 'to';
            write_client $client, 250, 'OK';
        }
        
        # RCPT TO
        elsif ( ( $next eq 'to' || $next eq 'to_or_data_start' ) && $cmd eq 'RCPT' && $data =~ /^to:\s*(.+)$/i ) {
            my $to = $1;
            if ( $to =~ /<(.*?)>/ ) {
                $to = $1;
            }
            if ( $to ) {
                $to =~ s/[\r\n]//gms;
                push @{ $mail{ to } ||= [] }, $to;
                $next = 'to_or_data_start';
                write_client $client, 250, 'OK';
            }
            else {
                reset_mail \%mail;
                $next = 'helo';
                write_client $client, 554, 'Require a recipient';
            }
        }
        
        # DATA (start)
        elsif ( ( $next eq 'data_start' || $next eq 'to_or_data_start' ) && $cmd eq 'DATA' ) {
            
            # check minimal
            unless( $mail{ from } && $mail{ to } && $mail{ helo } ) {
                write_client $client, 221, 'Require HELO, RCPT TO and MAIL FROM';
                reset_mail \%mail;
                $next = 'helo';
            }
            
            # all good, handle by doorman, start reading data
            else {
                
                my ( $ok, $reject_message, $err ) = ( 1 );
                
                if ( $self->doorman ) {
                    $mail{ doorman_session_cache } ||= {};
                    foreach my $to( @{ $mail{ to } } ) {
                        eval {
                            ( $ok, $reject_message, my $session_ref ) = $self->defender->handle_safe( envelope => {
                                rcpt_to   => $to,
                                mail_from => $mail{ from },
                                ( map {
                                    ( $_ => $mail{ $_ } )
                                } grep {
                                    defined $mail{ $_ }
                                } qw/ client_name client_addr client_helo client_ident / )
                            } );
                            $mail{ doorman_session_cache }->{ $to } = $session_ref;
                        };
                        $err = $@;
                        last if $err || ! $ok;
                    }
                    
                    if ( $err ) {
                        $self->defender->logger->error( "Error in handling mail [doorman]: $err" );
                        $ok = 0;
                        $reject_message = '450 Temporary problem';
                    }
                }
                
                
                # failed -> end here
                unless( $ok ) {
                    if ( $reject_message =~ /^(\d{3})\s+(.+?)$/ ) {
                        write_client $client, $1, $2;
                    }
                    else {
                        write_client $client, 500, $reject_message;
                    }
                    $next = 'helo_or_quit';
                    reset_mail \%mail;
                }
                
                # looking good, collect data for detective
                else {
                    
                    # init temp file, if detective enabled
                    if ( $self->detective ) {
                        my ( $th, $tn ) = tempfile( $self->detective->spool_dir. '/mail-XXXXXX', UNLINK => 0 );
                        $mail{ mime_fh }   = $th;
                        $mail{ mime_file } = $tn;
                    }
                    
                    write_client $client, 354, 'End with "." on a line by itself';
                    $next = 'data_read';
                }
            }
            
        }
        
        # DATA (content)
        elsif ( $next eq 'data_read' ) {
            
            # after last line
            if ( $cmd eq '.' ) {
                
                # anyway:
                $next = 'helo_or_quit';
                
                my ( $ok, $reject_message, $err, $final_state ) = ( 1 );
                
                # no detective -> accept mail
                unless( $self->detective ) {
                    $self->defender->logger->debug2( "Mail accepted" );
                    write_client $client, 250, 'OK';
                }
                
                # having detetctive enabled? Get his andser!
                else {
                    close delete $mail{ mime_fh };
                    
                    foreach my $to( @{ $mail{ to } } ) {
                        my ( $th, $tn ) = tempfile( $self->detective->spool_dir. '/mail-XXXXXX', UNLINK => 0 );
                        copy( $mail{ mime_file }, $tn );
                        
                        eval {
                            ( $ok, $reject_message, $final_state ) = $self->detective->handle_safe( data => {
                                file => $tn,
                                from => $mail{ from },
                                to   => $to,
                                args => {
                                    doorman_session_data => defined $mail{ doorman_session_cache }
                                        && defined $mail{ doorman_session_cache }->{ $to }
                                        ? { %{ $mail{ doorman_session_cache }->{ $to } } }
                                        : undef
                                    ,
                                }
                            } );
                        };
                        $err = $@;
                        close $th if $th;
                        
                        last if $err || ! $ok;
                    }
                    
                    # error in handling
                    if ( $err ) {
                        $self->defender->logger->error( "Error in handling mail [detective]: $err" );
                        write_client $client, 450, "Temporary problem";
                    }
                    
                    # at least no error
                    else {
                        
                        # parse response from detective
                        my ( $response_state, $response_msg )
                            = $self->defender->detective_response( $final_state );
                        
                        # say: OK
                        if ( $response_state eq 'discard' || $response_state eq 'accept' ) {
                            write_client $client, 250, "OK";
                        }
                        
                        # say: not OK
                        else {
                            my ( $rcode, $rmsg );
                            if ( $response_msg =~ /^(\d{3})\s+(.+)$/ ) {
                                $rcode = $1;
                                $rmsg = $2;
                            }
                            else {
                                $rcode = 500;
                                $rmsg = $response_msg;
                            }
                            write_client $client, $rcode, $rmsg;
                        }
                    }
                }
                
                # reset all for next mail
                reset_mail \%mail;
            }
            
            # collect lines (if detective enabled)
            elsif ( $self->detective ) {
                my $fh = $mail{ mime_fh };
                print $fh $line;
            }
        }
        
        # HELO or QUIT
        elsif ( ( $next eq 'helo_or_quit' || $next eq 'quit' ) && $cmd eq 'QUIT' ) {
            $next = 'helo';
            write_client $client, 221, 'Thanks for the fish';
            reset_mail \%mail;
        }
        
        # OOPOS
        else {
            write_client $client, 502, 'This is not your mail server';
            $next = 'helo';
            reset_mail \%mail;
        }
    }
}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

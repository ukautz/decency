package Mail::Decency::Core::NetServer::SMTPDetective;

=head1 NAME

Mail::Decency::Core::NetServer::Postfix

=head1 DESCRIPTION


=head1 SYNOPSIS


=cut

use strict;
use warnings;
use base qw/ Mail::Decency::Core::NetServer /;
use Data::Dumper;
use File::Temp qw/ tempfile /;

use constant ENDL => "\r\n";


=head1

=head1 METHODS


=head2 post_configure

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

sub reset_mail($) {
    my $mail_ref = shift;
    close delete $mail_ref->{ mime_fh }
        if ( defined $mail_ref->{ mime_fh } );
    if ( my $file = delete $mail_ref->{ mime_file } ) {
        unlink( $file ) if -f $file;
    }
    delete $mail_ref->{ $_ } for keys %$mail_ref;
}

sub child_init_hook {
    my ( $self ) = @_;
    $self->detective->setup();
}

sub detective {
    shift->{ server }->{ detective };
}

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
        
        # HELO / EHLO
        if ( $next eq 'helo' && $cmd =~ /^(?:HE|EH)LO$/ ) {
            $next = 'from';
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
        elsif ( $next eq 'to' && $cmd eq 'RCPT' && $data =~ /^to:\s*(.+)$/i ) {
            $mail{ to } = $1;
            if ( $mail{ to } =~ /<(.*?)>/ ) {
                $mail{ to } = $1;
            }
            if ( $mail{ to } ) {
                $mail{ to } =~ s/[\r\n]//gms;
                $next = 'data_start';
                write_client $client, 250, 'OK';
            }
            else {
                reset_mail \%mail;
                $next = 'helo';
                write_client $client, 554, 'Require a recipient';
            }
        }
        
        # DATA (start)
        elsif ( $next eq 'data_start' && $cmd eq 'DATA' ) {
            my ( $th, $tn ) = tempfile( $self->detective->spool_dir. '/mail-XXXXXX', UNLINK => 0 );
            $mail{ mime_fh }   = $th;
            $mail{ mime_file } = $tn;
            write_client $client, 354, 'End with "." on a line by itself';
            $next = 'data_read';
        }
        
        # DATA (content)
        elsif ( $next eq 'data_read' ) {
            if ( $cmd eq '.' ) {
                close delete $mail{ mime_fh };
                my ( $ok, $reject_message );
                eval {
                    ( $ok, $reject_message ) = $self->detective->handle_safe( {
                        file => $mail{ mime_file },
                        from => $mail{ from },
                        to   => $mail{ to },
                    } );
                };
                
                # error in handling
                if ( $@ ) {
                    write_client $client, 450, 'Temporary problem';
                    $self->detective->logger->error( "Error in handling mail: $@" );
                    $next = 'helo_or_quit';
                }
                
                # mail rejected
                elsif ( ! $ok ) {
                    $self->detective->logger->debug2( "Mail rejected ($reject_message)" );
                    write_client $client, 554, $reject_message || 'Rejected';
                    $next = 'helo_or_quit';
                }
                
                # mail accepted
                else {
                    $self->detective->logger->debug2( "Mail accepted" );
                    write_client $client, 250, 'Bye';
                    $next = 'helo_or_quit';
                }
                
                # reset all for next mail
                reset_mail \%mail;
            }
            else {
                my $fh = $mail{ mime_fh };
                print $fh $line;
            }
        }
        
        # HELO or QUIT
        elsif ( $next eq 'helo_or_quit' && ( $cmd =~ /^(?:HE|EH)LO$/ || $cmd eq 'QUIT' ) ) {
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

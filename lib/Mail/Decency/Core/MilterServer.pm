package Mail::Decency::Core::MilterServer;

=head1 NAME

Mail::Decency::Core::MilterServer

=head1 DESCRIPTION


=head1 SYNOPSIS


=cut

use Mouse;
use base qw/ Sendmail::PMilter /;
use Sendmail::PMilter qw/ :all /;
use Data::Dumper;
use Socket;
use File::Temp qw/ tempfile /;
use File::Copy qw/ copy /;
use Scalar::Util qw/ weaken /;
use POSIX;

BEGIN {
    $ENV{ PMILTER_DISPATCHER } = 'prefork';
    #$Sendmail::PMilter::DEBUG = 1;
    
    use Sendmail::PMilter::Context;
    
    {
        no warnings 'redefine';
        
        sub Sendmail::PMilter::Context::addheader($$$) {
            my $this = shift;
            my $header = shift || DD::cop_it "addheader: no header name\n";
            
            # fix (if value is "0")
            my $value = shift;
            DD::cop_it "addheader: no header value\n"
                unless defined $value;
            
            DD::cop_it "addheader: called outside of EOM\n" if ($this->{cb} ne 'eom');
            DD::cop_it "addheader: SMFIF_ADDHDRS not in capability list\n" unless ($this->{callback_flags} & Sendmail::PMilter::Context::SMFIF_ADDHDRS);
            $this->write_packet( Sendmail::PMilter::Context::SMFIR_ADDHEADER, "$header\0$value\0");
            1;
        }
    }
}

=head1

=head1 METHODS

=head2 parent

Backlink to parent instance.. normally a Mail::Decency::Defender

=cut

has parent => ( is => 'ro', required => 1, weak_ref => 1 );


=head2 current_context : Sendmail::PMilter::Context

Set to the current context

=cut

has current_context => ( is => 'rw', isa => 'Sendmail::PMilter::Context', weak_ref => 1 );


=head2 BUILD

=cut

sub BUILD {
    my ( $self ) = @_;
    
    weaken( my $self_weak = $self );
    
    # get config
    my $config_ref = $self->parent->config;
    
    # set connection
    $self->setconn( 'inet:'. $config_ref->{ server }->{ port }. '@'. $config_ref->{ server }->{ host } );
    
    # register defender
    $self->register( defender => { map {
        my $name = $_;
        my $meth = "callback_$name";
        ( $name => sub {
            my ( $ctx, @args ) = @_;
            $self->current_context( $ctx );
            return $self->can( $meth )
                ? do {
                    my $res = $self->$meth( $ctx, @args );
                    $res;
                }
                : SMFIS_CONTINUE
            ;
        } );
    } qw/ close connect helo abort envfrom envrcpt header eoh body eom / },
        SMFIF_ADDHDRS | SMFIF_CHGHDRS
    );
    
    my $parent_pid = $$;
    
    # dispatcher
    $self->set_dispatcher( my_prefork_dispatcher(
        child_init => sub {
            my ( $milter_server ) = @_;
            
            # try setup
            eval {
                
                # mark as child
                $self->delegate_meth( 'this_is_a_child' );
                
                # do setup
                $milter_server->parent->setup;
            };
            
            # catch error in setup
            if ( $@ ) {
                $self->parent->logger->error( "Failed to startup forked server: $@" );
                kill USR2 => $parent_pid;
                exit 0;
            }
            
            return ;
        },
        max_children => $config_ref->{ server }->{ instances }
    ) );
    
    #
    # catch: announce new client
    #
    
    # catch startup errors
    my $last_restart = time();
    my $fail_count = $config_ref->{ server }->{ instances } * 2 + 1;
    $SIG{ USR2 } = sub {
        my $now = time();
        my $diff = $now - $last_restart;
        $last_restart = $now;
        $fail_count -- if $diff < 3;
        kill TERM => $$ if $fail_count <= 0;
        return ;
    };
}



sub delegate_meth {
    my ( $self, $meth, @args ) = @_;
    return $self->parent->delegate_meth( $meth, @args );
}

sub my_prefork_dispatcher (@) {
    my %params = @_;
    my %children;
    
    my $child_dispatcher = sub {
        my $this = shift;
        my $lsocket = shift;
        my $handler = shift;
        my $max_requests = $this->get_max_requests() || $params{max_requests_per_child} || 100;
        my $i = 0;
    
        local $SIG{PIPE} = 'IGNORE'; # so close_callback will be reached
    
        my $siginfo = exists($SIG{INFO}) ? 'INFO' : 'USR1';
        local $SIG{$siginfo} = sub {
            warn "$$: requests handled: $i\n";
        };
    
        # call child_init handler if present
        if (defined $params{child_init}) {
            my $method = $params{child_init};
            $this->$method();
        }
    
        while ($i < $max_requests) {
            my $socket = $lsocket->accept();
            next if $!{EINTR};
    
            $i++;
            &$handler($socket);
            $socket->close();
        }
    
        # call child_exit handler if present
        if (defined $params{child_exit}) {
            my $method = $params{child_exit};
            $this->$method();
        }
    };
    
    # Propagate some signals down to the entire process group.
    my $killall = sub {
        my $sig = shift;
        kill 'TERM', keys %children;
        exit 0;
    };
    local $SIG{INT} = $killall;
    local $SIG{QUIT} = $killall;
    local $SIG{TERM} = $killall;
    
    setpgrp();
    
    sub {
        my $this = $_[0];
        my $max_children = $this->get_max_interpreters() || $params{max_children} || 10;
        my $started = 0;
        while (1) {
            while ( scalar keys %children < $max_children) {
                my $pid = fork();
                DD::cop_it "fork: $!" unless defined($pid);
                
                if ($pid) {
                    # Perl reset these to IGNORE.  Restore them.
                    $SIG{INT}  = $killall;
                    $SIG{QUIT} = $killall;
                    $SIG{TERM} = $killall;
                    $children{ $pid } = 1;
                } else {
                    # Perl reset these to IGNORE.  Set to defaults.
                    $SIG{INT} = 'DEFAULT';
                    $SIG{QUIT} = 'DEFAULT';
                    $SIG{TERM} = 'DEFAULT';
                    &$child_dispatcher(@_);
                    exit 0;
                }
            }
    
            # Wait for a pid to exit, then loop back up to fork.
            my $pid = wait();
            delete $children{$pid} if ($pid > 0);
        }
    };
}


=head2 callback_connect

=cut

sub callback_connect {
    my ( $self, $ctx, $hostname, $addr ) = @_;
    my ( $port, $ip ) = unpack_sockaddr_in( $addr );
    $ctx->setpriv( { client_name => $hostname, client_ip => inet_ntoa( $ip ) } );
    return SMFIS_CONTINUE; 
}

=head2 callback_helo

=cut

sub callback_helo {
    my ( $self, $ctx, $helo ) = @_;
    eval {
        my $data_ref = $ctx->getpriv || {};
        $ctx->setpriv( { %$data_ref, client_helo => $helo } );
    };
    return SMFIS_CONTINUE; 
}


=head2 callback_envrcpt

Tell the Doorman

=cut

sub callback_envrcpt {
    my ( $self, $ctx, $rcpt ) = @_;
    
    my $data_ref = $ctx->getpriv || {};
    my $session_ref = {
        mail_from   => $ctx->getsymval( '{mail_addr}' ),
        rcpt_to     => $rcpt,
        client_helo => $data_ref->{ client_helo } || '',
        client_name => $data_ref->{ client_name } || '',
        client_addr => $data_ref->{ client_ip } || '',
        sasl_user   => $ctx->getsymval( '{auth_authen}' ) || '',
        sasl_method => $ctx->getsymval( '{auth_type}' ) || '', 
    };
    
    push @{ $data_ref->{ rcpt_addr } ||= [] }, $rcpt;
    
    ( my $ok, my $err, $session_ref ) = $self->parent->handle_safe( envelope => $session_ref );
    
    if ( $ok ) {
        $data_ref->{ doorman_session_data } = $session_ref;
        $ctx->setpriv( $data_ref );
        return SMFIS_CONTINUE;
    }
    else {
        my ( $code, $msg ) = split( / /, $err, 2 );
        ( $code, my $xcode ) = $code =~ /^4\d\d/
            ? ( 451, '4.7.0' )
            : ( 554, '5.7.1' )
        ;
        $ctx->setreply( $code => $xcode => $msg );
        return SMFIS_REJECT;
    }
}


=head2 callback_header

Collect headers into priv data and write to temp file (used for detective

=cut

sub callback_header {
    my ( $self, $ctx, $name, $value ) = @_;
    
    # write headers to temp file
    if ( $self->parent->has_detective ) {
        
        my $data_ref = $ctx->getpriv || {};
        push @{ $data_ref->{ headers }->{ $name } ||= [] }, $value;
        
        my $fh = $self->_open_mime( $ctx );
        $data_ref->{ headers } ||= {};
        1 while chomp( $value );
        print $fh "$name: $value\015\012";
        close $fh;
    }
    
    return SMFIS_CONTINUE;
}

=head2 callback_body

Write body to temp file (if Detective used)

=cut

sub callback_body {
    my ( $self, $ctx, $body, $length ) = @_;
    
    if ( $self->parent->has_detective ) {
        my $fh = $self->_open_mime( $ctx );
        foreach my $line( split( /(?:\015\012|\015|\012)/, $body ) ) {
            1 while chomp( $line );
            print $fh "$line\015\012";
        }
        close $fh;
    }
    
    return SMFIS_CONTINUE;
}

=head2 callback_eom

Handle Detective (if enabled)

=cut

sub callback_eom {
    my ( $self, $ctx ) = @_;
    
    # Detective is disabled
    return SMFIS_CONTINUE
        unless $self->parent->has_detective;
    
    # get data
    my $data_ref = $ctx->getpriv || {};
    
    # get from
    my $mail_from = $ctx->getsymval( '{mail_addr}' );
    
    # get queeu id
    my $queue_id  = $ctx->getsymval( 'i' ) || ( defined $ctx->{ symbols } && defined $ctx->{ symbols }->{ N } && defined $ctx->{ symbols }->{ N }->{ i }
        ? $ctx->{ symbols }->{ N }->{ i } || undef
        : undef
    );
    
    # get detective
    my $detective = $self->parent->detective;
    
    # wheter we use reinjection or milter
    my $enforce_reinject = $self->parent->enforce_reinject;
    
    # perform Detective filter
    my ( $ok, $reject_message, $err );
    my $mime_changes_ref = {};
    my $final_state = 'ongoing';
    my @rctp_addr = @{ $data_ref->{ rcpt_addr } };
    my $rcpt_cnt = 0;
    
    # for each recipient
    foreach my $rcpt_to( @rctp_addr ) {
        my $rcpt_cnt++;
        my $is_last = $rcpt_cnt == scalar @rctp_addr;
        
        # using a copy for each filter
        my $mask = $detective->spool_dir. "/mail-XXXXXX";
        my ( $th, $tn ) = tempfile( $mask, UNLINK => 0 );
        copy( $data_ref->{ tempfile }, $tn );
        eval {
            ( $ok, $reject_message, my $status ) = $self->parent->handle_safe( data => {
                file => $tn,
                from => $mail_from,
                to   => $rcpt_to,
                args => {
                    # doorman_session_data => defined $data_ref->{ doorman_session_data }
                    #     ? { %{ $data_ref->{ doorman_session_data } } }
                    #     : undef
                    # ,
                    queue_id           => $queue_id,
                    no_session_cleanup => 1,
                }
            } );
            
            # get session
            my $session = $detective->session;
            
            # final if spam, virus or really last
            if ( $status eq 'spam' || $status eq 'virus' || $is_last ) {
                $is_last = 1;
                $mime_changes_ref = $session->mime_header_changes;
                $final_state = $status;
            }
            
            # cleanup session in any case
            $session->cleanup;
        };
        $err = $@;
        warn "Error in Detective: $err\n" if $err;
        close $th if $th;
        
        last if ! $enforce_reinject && ( $err || ! $ok || $is_last );
    }
    
    my ( $response_state, $response_msg ) = $self->parent->detective_response( $final_state );
    if ( $response_state ) {
        $ctx->setreply( 554, '5.7.1', $response_msg ) if $response_msg;
        if ( $error_state eq 'discard' ) {
            return SMFIS_DISCARD;
        }
        elsif ( $error_state eq 'reject' ) {
            return SMFIS_REJECT;
        }
    }
    
    
    # write altererd MIME
    eval {
        $mime_changes_ref ||= {};
        while( my ( $mode, $ref ) = each %$mime_changes_ref ) {
            if ( $mode eq 'replace' ) {
                while( my ( $name, $values_ref ) = each %$ref ) {
                    if ( defined( my $seen_ref = $data_ref->{ headers }->{ $name } ) ) {
                        my $exist_count = scalar @$seen_ref;
                        my $replace_count = scalar @$values_ref;
                        for ( my $i = 0; $i < $replace_count; $i++ ) {
                            if ( $i > $exist_count ) {
                                $ctx->addheader( $name, $values_ref->[$i] );
                            }
                            else {
                                $ctx->chgheader( $name, $i, $values_ref->[$i] );
                            }
                        }
                    }
                    else {
                        $ctx->addheader( $name, $_ ) for @$values_ref;
                    }
                }
            }
            
            elsif ( $mode eq 'add' ) {
                while( my ( $name, $values_ref ) = each %$ref ) {
                    $ctx->addheader( $name, $_ ) for @$values_ref;
                }
            }
        }
    };
    
    return SMFIS_CONTINUE;
}

=head2 callback_close

Cleanup on close

=cut

sub callback_close {
    my ( $self, $ctx ) = @_;
    my $data_ref = $ctx->getpriv || {};
    if ( defined $data_ref->{ tempfile } ) {
        unlink( $data_ref->{ tempfile } ) if -f $data_ref->{ tempfile };
    }
    return SMFIS_CONTINUE;
}

sub _open_mime {
    my ( $self, $ctx ) = @_;
    my $data_ref = $ctx->getpriv || {};
    unless ( defined $data_ref->{ tempfile } ) {
        my $mask = $self->parent->detective->spool_dir. "/mail-XXXXXX";
        my ( $th, $tn ) = tempfile( $mask, UNLINK => 0 );
        close $th;
        $data_ref->{ tempfile } = $tn;
        $ctx->setpriv( $data_ref );
    }
    
    open my $fh, '>>', $data_ref->{ tempfile }
        or DD::cop_it "Cannot open '$data_ref->{ tempfile }' for append: $!\n";
    return $fh;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

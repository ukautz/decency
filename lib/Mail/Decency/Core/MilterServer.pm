package Mail::Decency::Core::MilterServer;

=head1 NAME

Mail::Decency::Core::MilterServer

=head1 DESCRIPTION


=head1 SYNOPSIS


=cut

use Mouse;
use base qw/ Sendmail::PMilter /;
use Carp qw/ croak /;
use Sendmail::PMilter qw/ :all /;
use Data::Dumper;
use Socket;
use File::Temp qw/ tempfile /;
use File::Copy qw/ copy /;

BEGIN {
    $ENV{ PMILTER_DISPATCHER } = 'prefork';
    $Sendmail::PMilter::DEBUG = 1;
    
}

=head1

=head1 METHODS

=head2 parent

Backlink to parent instance.. normally a Mail::Decency::Defender

=cut

has parent => ( is => 'ro', required => 1 );

=head2 parent

Backlink to parent instance.. normally a Mail::Decency::Defender

=cut

has parent => ( is => 'ro', required => 1 );


=head2 BUILD

=cut

sub BUILD {
    my ( $self ) = @_;
    
    my $config_ref = $self->parent->config;
    $self->setconn( 'inet:'. $config_ref->{ server }->{ port }. '@'. $config_ref->{ server }->{ host } );
    $self->register( defender => { map {
        my $name = $_;
        my $meth = "callback_$name";
        ( $name => sub {
            my ( $ctx, @args ) = @_;
            return $self->can( $meth )
                ? do {
                    warn "** REPLY $meth: ". join( " || ", @args ). " **\n";
                    my $res = $self->$meth( $ctx, @args );
                    warn "-> RETURN $res\n";
                    $res;
                }
                : do {
                    warn "** REPLY DEFAULT FOR $name: ". join( " || ", @args ). " **\n";
                    SMFIS_CONTINUE
                }
            ;
        } );
    } qw/ close connect helo abort envfrom envrcpt header eoh body eom / }, SMFI_CURR_ACTS );
    $self->set_dispatcher( Sendmail::PMilter::prefork_dispatcher(
        child_init => sub {
            shift->parent->setup;
            return ;
        },
        max_children => $config_ref->{ server }->{ instances }
    ) );
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
    warn "ERR IN HELO $@\n";
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
        rcpt_addr   => $rcpt,
        client_helo => $data_ref->{ client_helo } || '',
        client_name => $data_ref->{ client_name } || '',
        client_addr => $data_ref->{ client_ip } || '',
        sasl_user   => $ctx->getsymval( '{auth_authen}' ) || '',
        sasl_method => $ctx->getsymval( '{auth_type}' ) || '', 
    };
    
    push @{ $data_ref->{ rcpt_addr } ||= [] }, $rcpt;
    $ctx->setpriv( $data_ref );
    
    my ( $ok, $err ) = $self->parent->handle_safe( envelope => $session_ref );
    
    if ( $ok ) {
        return SMFIS_CONTINUE;
    }
    else {
        my ( $code, $msg ) = split( / /, $err, 2 );
        ( $code, my $xcode ) = $code =~ /^4\d\d/
            ? ( 451, '4.7.0' )
            : ( 554, '5.7.1' )
        ;
        $self->setreply( $code => $xcode => $msg );
        return SMFIS_REJECT;
    }
}

sub callback_header {
    my ( $self, $ctx, $name, $value ) = @_;
    my $fh = $self->_open_mime( $ctx );
    warn "HEADER $name / $value\n";
    1 while chomp( $value );
    print $fh "$name: $value\015\012";
    close $fh;
    return SMFIS_CONTINUE;
}

sub callback_body {
    my ( $self, $ctx, $body, $length ) = @_;
    my $fh = $self->_open_mime( $ctx );
    foreach my $line( split( /(?:\015\012|\015|\012)/, $body ) ) {
        1 while chomp( $line );
        print $fh "$line\015\012";
    }
    close $fh;
    return SMFIS_CONTINUE;
}

sub callback_eom {
    my ( $self, $ctx ) = @_;
    
    my $data_ref = $ctx->getpriv || {};
    
    # oops
    unless ( $data_ref->{ rcpt_addr } ) {
        return SMFIS_REJECT;
    }
    
    print Dumper( $ctx );
    
    
    my $mail_from = $ctx->getsymval( '{mail_addr}' );
    my $queue_id  = $ctx->getsymval( 'i' ) || ( defined $ctx->{ symbols } && defined $ctx->{ symbols }->{ N } && defined $ctx->{ symbols }->{ N }->{ i }
        ? $ctx->{ symbols }->{ N }->{ i } || undef
        : undef
    );
    print "MAIL FROM: $mail_from / QUEUE ID ". ( $queue_id || "NONE" ). "\n";
    
    my ( $ok, $reject_message, $err, $mail );
    my @rctp_addr = @{ $data_ref->{ rcpt_addr } };
    my $rcpt_cnt = 0;
    foreach my $rcpt_to( @rctp_addr ) {
        my $rcpt_cnt++;
        my $is_last = $rcpt_cnt == scalar @rctp_addr;
        my $mask = $self->parent->detective->spool_dir. "/mail-XXXXXX";
        my ( $th, $tn ) = tempfile( $mask, UNLINK => 0 );
        copy( $data_ref->{ tempfile }, $tn );
        eval {
            ( $ok, $reject_message ) = $self->parent->handle_safe( data => {
                file => $tn,
                from => $mail_from,
                to   => $rcpt_to,
                args => {
                    queue_id           => $queue_id,
                    no_session_cleanup => $is_last
                }
            } );
            
            if ( $is_last ) {
                $mail = $self->parent->detective->session->mime->stringify;
                $self->parent->detective->session->cleanup;
            }
        };
        $err = $@;
        warn "Error in Detective: $err\n" if $err;
        close $th if $th;
        
        last if $err || ! $ok;
    }
    
    #$self->parent
    
    # write altererd MIME
    if ( $mail ) {
        print "*** MAIL ***\n$mail\m*** MAIL ***\n\n";
        $ctx->replacebody( $mail );
    }
    
    #return SMFIS_CONTINUE;
    return SMFIS_CONTINUE;
}

# sub callback_abort {
#     return _cleanup( @_ );
# }
sub callback_close {
    return _cleanup( @_ );
}

sub _cleanup {
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
        or die "Cannot open '$data_ref->{ tempfile }' for append: $!\n";
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

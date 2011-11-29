package Mail::Decency::Core::NetServer;

=head1 NAME

Mail::Decency::Core::NetServer

=head1 DESCRIPTION


=head1 SYNOPSIS


=cut

use base qw/ Net::Server::PreFork /;
use Data::Dumper;
use Net::Server::SIG qw(register_sig check_sigs);


=head1

=head1 METHODS


=head2 post_configure

=cut

sub child_init_hook {
    my ( $self ) = @_;
    warn "child-init $$\n";
    $self->doorman->setup();
}

sub process_request {
    my ( $self ) = @_;
    my $client = $self->{ server }->{ client };
    my %attrib;
    while( my $line = <$client> ) {
        chomp $line;
        unless( $line ) {
            my $answer = eval { $self->doorman->handle_safe( \%attrib ) };
            if ( $@ ) {
                warn "ERR> $@\n";
                warn "OUT> action=450 Temporary problem\n";
                print $client "action=450 Temporary problem\n";
                print $client "\n";
            }
            else {
                warn "OUT> action=$answer->{ action }\n";
                print $client "action=$answer->{ action }\n";
                print $client "\n";
            }
            %attrib = ();
            next;
        }
        
        my ( $key, $value ) = split( /=/, $line, 2 );
        $attrib{ $key } = $value;
        warn "<< IN '$line'\n";
    }
    
    $self->done(1);
}

sub doorman {
    shift->{ server }->{ doorman };
}


### child process which will accept on the port
sub run_childxx {
  my $self = shift;
  my $prop = $self->{server};

  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub {
    $self->child_finish_hook;
    exit;
  };
  $SIG{PIPE} = 'IGNORE';
  $SIG{CHLD} = 'DEFAULT';
  $SIG{HUP}  = sub {
    if (! $prop->{connected}) {
      $self->child_finish_hook;
      exit;
    }
    $prop->{SigHUPed} = 1;
  };

  # Open in child at start
  open($prop->{lock_fh}, ">$prop->{lock_file}")
    || $self->fatal("Couldn't open lock file \"$prop->{lock_file}\"[$!]");

  $self->log(4,"Child Preforked ($$)\n");

  delete $prop->{$_} foreach qw(children tally last_start last_process);

  $self->child_init_hook;
  
  while( 1 ) {
    
      ### accept connections
      while( $self->accept() ){
    
        $prop->{connected} = 1;
        print _WRITE "$$ processing\n";
    
        eval { $self->run_client_connection };
        if ($@) {
          print _WRITE "$$ exiting\n";
          die $@;
        }
    
        last if $self->done;
    
        $prop->{connected} = 0;
        print _WRITE "$$ waiting\n";
    
      }
  }

  $self->child_finish_hook;

  print _WRITE "$$ exiting\n";
  exit;

}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

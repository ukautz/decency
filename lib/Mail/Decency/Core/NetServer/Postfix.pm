package Mail::Decency::Core::NetServer::Postfix;

=head1 NAME

Mail::Decency::Core::NetServer::Postfix

=head1 DESCRIPTION


=head1 SYNOPSIS


=cut

use base qw/ Mail::Decency::Core::NetServer /;
use Data::Dumper;


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
        last unless $line;
        my ( $key, $value ) = split( /=/, $line, 2 );
        $attrib{ $key } = $value;
        warn "<< IN '$line'\n";
    }
    
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
    $self->{ server }->{ client }->close;
}

sub doorman {
    shift->{ server }->{ doorman };
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

package Mail::Decency::Core::NetServer::Doorman;

=head1 NAME

Mail::Decency::Core::NetServer::Doorman

=head1 DESCRIPTION


=head1 SYNOPSIS


=cut

use strict;
use warnings;
use base qw/ Mail::Decency::Core::NetServer /;
use Data::Dumper;


=head1

=head1 METHODS


=head2 post_configure

=cut

sub child_init_hook {
    my ( $self ) = @_;
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
                $ENV{ POSTFIX_DEBUG } && warn "OUT> action=450 Temporary problem\n";
                print $client "action=450 Temporary problem\n";
                print $client "\n";
            }
            else {
                $ENV{ POSTFIX_DEBUG } && warn "OUT> action=$answer->{ action }\n";
                print $client "action=$answer->{ action }\n";
                print $client "\n";
            }
            %attrib = ();
            next;
        }
        
        my ( $key, $value ) = split( /=/, $line, 2 );
        $attrib{ $key } = $value;
        $ENV{ POSTFIX_DEBUG } && warn "<< IN '$line'\n";
    }
    
    eval { close $client; 1; } || warn "OOps: $@";
    undef $client;
    delete $self->{ server }->{ client };
    
    $self->done(1);
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

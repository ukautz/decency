package Mail::Decency::Policy::AWL;

use Mouse;
use mro 'c3';
extends qw/
    Mail::Decency::Policy::Core
/;

use version 0.74; our $VERSION = qv( "v0.1.4" );

use Data::Dumper;

=head1 NAME

Mail::Decency::Policy

=head1 SYNOPSIS

    use POE::Component::Server::Postfix;
    use Mail::DecencyPolicy;
    use Mail::DecencyPolicy::AWL;
    
    my $policy = Mail::DecencyPolicy->new( {
        config => '/etc/pdp/config'
    } );
    
    my $server = POE::Component::Server::Postfix->new(
        port    => 12345,
        host    => '127.0.0.1',
        filter  => 'Plain',
        handler => $policy->get_handler()
    );
    POE::Kernel->run;

=head1 DESCRIPTION

Postfix:DecencyPolicy is a bunch of policy servers which c

Base class for all decency policy handlers.

=cut 

sub init {}
sub handle {}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

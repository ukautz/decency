package Mail::Decency::Doorman::Cookbook;

use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

Mail::Decency::Doorman::Cookbook - How to write a Doorman module

=head1 DESCRIPTION

This module contains a description on howto write a Detective module.

=head1 EXAMPLES

Hope this helps to understand what you can do. Have a look at the existing modules for more examples. Also look at L<Mail::Decency::Doorman::Core> for available methods.

=head2 SIMPLE EXAMPLE


    package Mail::Decency::Doorman::MyModule;
    
    use Mouse;
    use mro 'c3';
    extends 'Mail::Decency::Doorman::Core';
    
    has some_key => ( is => 'rw', isa => 'Bool', default => 0 );
    
    #
    # The init method is kind of a new or BUILD method, which should
    #   init all configurations from the YAML file
    #
    sub init {
        my ( $self ) = @_;
        
        # in YAML:
        #   ---
        #   some_key: 1
        $self->some_key( 1 )
            if $self->config->{ some_key };
    }
    
    #
    # The handle method will be called by the Detective server each time a new
    #   mail is filtered
    #
    
    sub handle {
        my ( $self ) = @_;
        
        # accesss sender:
        #   $self->from = sender address
        #   $self->from_domain = sender domain
        #   $self->from_prefix = sender username
        # 
        # accesss recipient:
        #   $self->to = recipient address
        #   $self->to_domain = recipient domain
        #   $self->to_prefix = recipient username
        #
        # accesss sender ip, host- and heloname:
        #   $self->ip = sender ip
        #   $self->helo = sender HELO name
        #   $self->hostname = sender hostname
        #
        # all other attribsutes
        #   $self->attrs->{ some_name };
        #       see http://www.postfix.org/SMTPD_POLICY_README.html
        
        # add spam score (throws exception, if threshold reached)
        $self->add_spam_score( -300,
            message => "Message for X-Decency-Detail header",
            detail  => "Reject message for SMTP REJECT",
            #message_and_detail => "single message for both"
        ) if $self->ip eq '123.123.123.0';
        
        # go to a final state (throws exception)
        $self->go_final_state( OK => "Mail is accepted" )
            if $self->to_domain eq 'something.tld';
        $self->go_final_state( REJECT => "No, i dont want this" )
            if $self->from_domain eq 'acme.tld';
        $self->go_final_state( 454 => "Please, try later" )
            if $self->to_domain 'yadda.tld';
        
        # access the datbaase
        my $data_ref = $self->database->get( schema => table => $search_ref );
        $data_ref->{ some_attrib } = time();
        $self->database->set( schema => table => $search_ref, $data_ref );
        
        # access the cache
        my $cached_ref = $self->cache->get( "cache-name" ) || { something => 1 };
        $cached_ref->{ something } ++;
        $self->cache->set( "cache-name" => $cached_ref );
        
        # set a flag for later evaluation (eg in Detective)
        $self->set_flag( 'bla' );
        $self->logger->info( "What can i say?" ) if $self->has_flag( "blub" );
        $self->del_flag( 'nada' ) if time() % 9999 = 33;
        
        # open a file and let the server take care of the closing
        my $file_handle = $self->open_file( '/tmp/some-file', '<', 'Exception text );
        
        # access session data
        warn "> CURRENT SPAM SCORE ". $self->session->spam_score. "\n";
    }

=head1 INCLUDE MODULE

To include the module, simple add it in your Doorman server configuration

=head2 YAML

In doorman.yml ...

    ---
    
    # ..
    
    modules:
        - MyModule:
            some_key: 1
        - MyOtherModule: /path/to/my-module.yml
    

=head2 PERL

    my $doorman = Mail::Decency::Doorman->new(
        # ..
        modules => [
            { MyModule => { some_key => 1 } }
        ]
    );

=head1 HOWTO

=head2 INTER-MODULE COMMUNICATION

You can use the (get|set|del|has)_flag-methods to communicate informations. The flags will also be transported in the decency X-Decency-Details header to the Detective (if forward_scoring is enabled)

    # in module 1, ran before module 2
    $self->set_flag( 'i_was_here' );
    
    # in module 2, after module 1 - even on another server
    if ( $self->has_flag( 'i_was_here' ) ) {
        # yadda
    }

If you require more complex data, you can use the session's (set|get|del)_val methods. Those will not be passed in the header, thus other servers cannot read them.

    # in module 1, ran before module 2 (both on one server)
    $self->session->set_val( 'whatever', { a => 123 } );
    
    # in module 2 on the same server
    my $xy = $self->session->get_val( 'whatever' ) || { a => 0 };
    if ( $xy->{ a } > 0 ) {
        # yadda
    }

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

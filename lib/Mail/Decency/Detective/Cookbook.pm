package Mail::Decency::Detective::Cookbook;

use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.1.4" );

=head1 NAME

Mail::Decency::Detective::Cookbook - How to write a Detective module

=head1 DESCRIPTION

This module contains a description on howto write a Detective module.

=head1 EXAMPLES

Hope this helps to understand what you can do. Have a look at the existing modules for more examples. Also look at L<Mail::Decency::Detective::Core> for available methods.

=head2 SIMPLE EXAMPLE


YAML Configuration

    ---
    
    some_easy_param: 1
    some_key: some_value


    package Mail::Decency::Detective::MyModule;
    
    use Mouse;
    extends qw/
        Mail::Decency::Detective::Core
    /;
    
    has some_easy_param => ( is => 'rw', isa => 'Bool', default => 0 );
    has some_key => ( is => 'rw', isa => 'Str', default => '' );
    
    #
    # The init method is kind of a new or BUILD method, which should
    #   init all configurations from the YAML file
    #
    sub init {
        my ( $self ) = @_;
        
        # add params, which does not need extra validation or you just
        #   want to rely on the Mouse validation (eg Bool accepts 0 or 1 and would
        #   throw an error)
        $self->add_config_params( qw/ some_easy_param / );
        
        # check
        die "some_key has to contain 'some'"
            unless ( $self->config->{ some_key } || "" ) =~ /some/;
        # set value
        $self->some_key( $self->config->{ some_key } );
    }
    
    #
    # The handle method will be called by the Detective server each time a new
    #   mail is filtered
    #
    
    sub handle {
        my ( $self ) = @_;
        
        # get the temporary queue file
        my $file = $self->file;
        
        # read the size
        my $size = $self->file_size;
        
        # manipulate the MIME::Entity object of the current
        $self->mime_header( add => 'X-MyModule' => 'passed' );
        
        # or access directly
        $self->mime->head->replace( SomeHeader => 'somevalue' );
        
        # announce changes
        $self->mime_has_changed;
        
        # get sender and recipient
        my $sender = $self->from;
        my $recipient = $self->to;
        
        # access the datbaase
        my $data_ref = $self->database->get( schema => table => $search_ref );
        $data_ref->{ some_attrib } = time();
        $self->database->get( schema => table => $search_ref, $data_ref );
        
        # access the cache
        my $cached_ref = $self->cache->get( "cache-name" ) || { something => 1 };
        $cached_ref->{ something } ++;
        $self->cache->set( "cache-name" => $cached_ref );
        
    }

=head2 SPAM FILTER EXAMPLE

    package Mail::Decency::Detective::MySpamFilter;
    
    use Mouse;
    extends qw/
        Mail::Decency::Detective::Core::Spam
    /;
    
    
    sub handle {
        my ( $self ) = @_;
        
        # throws exception if spam is recognized
        $self->add_spam_score( -100, "You shall not send me mail" )
            if $self->from eq 'evil@sender.tld';
        
    }

=head2 VIRUS FILTER EXAMPLE

    package Mail::Decency::Detective::MyVirusFilter;
    
    use Mouse;
    extends qw/
        Mail::Decency::Detective::Core::Virus
    /;
    
    sub handle {
        my ( $self ) = @_;
        
        # throws exception
        if ( time() % 86400 == 0 ) {
            $self->found_virus( "Your daily virus" );
        }
    }

=head2 HOOKS

There are two kinds of hooks which can be implemented by any modules. They exist, because not necessary all modules will be run in every session (eg if the first recognizes the mail as spam and throws an exception).

=head3 PRE FINISH HOOK

Called after the modules are processed. Has to return the status ("virus", "spam", "drop" or "ok") and the final code (DETECTIVE_FINAL_* from L<Mail::Decency::Detective::Core::Constants>).

    package Mail::Decency::Detective::MyPreHook;
    
    use Mouse;
    extends 'Mail::Decency::Detective::Core';
    use Mail::Decency::Detective::Core::Constants;
    
    # example from the HoneyCollector modules, which
    #   assures marked mails to be collected
    sub hook_pre_finish {
        my ( $self, $status ) = @_;
        
        # has been flagged..
        return ( $status, DETECTIVE_FINAL_OK )
            if ! $self->session->has_flag( 'honey' )
            || $self->session->has_flag( 'honey_collected' )
        ;
        
        # collect the honey
        $self->_collect_honey();
        
        # drop the mail
        return ( 'drop', DETECTIVE_FINAL_OK );
    }

=head2 POST FINISH HOOK

Called after the finish_(ok|spam|virus) methods. Takes the status as arguments and has to return the status and the final code.

    package Mail::Decency::Detective::MyPreHook;
    
    use Mouse;
    extends 'Mail::Decency::Detective::Core';
    use Mail::Decency::Detective::Core::Constants;
    
    sub hook_post_finish {
        my ( $self, $status ) = @_;
        
        # force to pass all recognized virus and spams..
        if ( $status eq 'virus' || $status eq 'spam' ) {
            return ( ok => DETECTIVE_FINAL_OK );
        }
        
        # delete all mails recognized as OK
        elsif ( $status eq 'ok' ) {
            return ( drop => DETECTIVE_FINAL_OK );
        }
        
        # bounce mails supposed to be dropped
        elsif ( $status eq 'drop' ) {
            return ( ok => DETECTIVE_FINAL_ERROR );
        }
    }

=head1 INCLUDE MODULE

To include the module, simple add it in your contnet filter

=head2 YAML

In detective.yml ...

    ---
    
    # ..
    
    modules:
        - MyModule:
            some_key: 1
        - MyModule: /path/to/my-module.yml
    

=head2 PERL

    my $detective = Mail::Decency::Detective->new(
        # ..
        modules => [
            { MyModule => { some_key => 1 } }
        ]
    );

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

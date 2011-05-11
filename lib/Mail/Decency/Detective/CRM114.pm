package Mail::Decency::Detective::CRM114;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Detective::Core::Cmd
    Mail::Decency::Detective::Core::Spam
    Mail::Decency::Detective::Core::User
    Mail::Decency::Detective::Core::WeightTranslate
/;

use version 0.74; our $VERSION = qv( "v0.1.6" );

use Data::Dumper;

=head1 NAME

Mail::Decency::Detective::CRM114

=head1 DESCRIPTION AND CONFIG

L<http://www.decency-antispam.org/docs/detective/crm114>

=head1 CLASS ATTRIBUTES

=cut

has cmd_check => (
    is      => 'rw',
    isa     => 'Str',
    default => '/usr/share/crm114/mailreaver.crm --fileprefix=%user% -u %user% --report_only'
);

has cmd_learn_spam => (
    is      => 'rw',
    isa     => 'Str',
    default => '/usr/share/crm114/mailfilter.crm --fileprefix=%user% -u %user% --learnspam'
);

has cmd_unlearn_spam => (
    is      => 'rw',
    isa     => 'Str',
    default => '/usr/share/crm114/mailfilter.crm --fileprefix=%user% -u %user% --learngood'
);

has cmd_learn_ham => (
    is      => 'rw',
    isa     => 'Str',
    default => '/usr/share/crm114/mailfilter.crm --fileprefix=%user% -u %user% --learngood'
);

has cmd_unlearn_ham => (
    is      => 'rw',
    isa     => 'Str',
    default => '/usr/share/crm114/mailfilter.crm --fileprefix=%user% -u %user% --learnspam'
);

=head1 METHODS


=head2 init

=cut

sub init {}


=head2 handle_filter_result

=cut

sub handle_filter_result {
    my ( $self, $result ) = @_;
    
    my %header;
    
    # parse result
    my %parsed = map {
        my ( $n, $v ) = /^X-CRM114-(\S+?):\s+(.*?)$/;
        ( $n => lc( $v ) );
    } grep {
        /^X-CRM114-/;
    } split( /\n/, $result );
    
    # found status ?
    if ( $parsed{ Status } ) {
        my $weight = 0;
        
        my $status = index( $parsed{ Status }, 'spam' ) > -1
            ? 'spam'
            : ( index( $parsed{ Status }, 'good' ) > -1
                ? 'good'
                : 'unsure'
            )
        ;
        my @info = ( "CRM114 status: $status" );
        
        # translate weight from crm114 to our requirements
        if ( $self->has_weight_translate ) {
            
            # extract weight
            ( $weight ) = $parsed{ Status } =~ /^.*?\(\s+(\-?\d+\.\d+)\s+\).*?/;
            my $orig_weight = $weight;
            
            # remember info for headers
            push @info, "CRM114 score: $orig_weight";
            
            # translate weight
            $weight = $self->translate_weight( $orig_weight );
            
            $self->logger->debug0( "Translated score from '$orig_weight' to '$weight'" );
        }
        elsif ( $status eq 'spam' ) {
            $weight = $self->weight_spam;
            $self->logger->debug0( "Use spam status, set score to '$weight'" );
        }
        elsif ( $status eq 'good' ) {
            $weight = $self->weight_innocent;
            $self->logger->debug0( "Use good status, set score to '$weight'" );
        }
        
        # add weight to content filte score
        return $self->add_spam_score( $weight, \@info );
    }
    
    else {
        $self->logger->error( "Could not retreive status from CRM114 result '$result'" );
    }
    
    # return ok
    return ;
}


=head2 get_user_fallback

CRM114 runs normally with $USER_HOME/.crm114 .. this fallback method implements that. As long as no "cmd_user" is set, it will be used.

=cut

sub get_user_fallback {
    my ( $self ) = @_;

    my ( $user, $domain ) = split( /@/, $self->to, 2 );
    return unless $user;
    my $uid = getpwnam( $user );
    return unless $uid;
    $user = ( getpwuid( $uid ) )[-2];
    $user .= "/.crm114";
    
    return $user;
}


=head1 SEE ALSO

=over

=item * L<Mail::Decency::Detective::Core::Cmd>

=item * L<Mail::Decency::Detective::Core::Spam>

=item * L<Mail::Decency::Detective::Core::WeightTranslate>

=item * L<Mail::Decency::Detective::Bogofilter>

=item * L<Mail::Decency::Detective::DSPAM>

=back

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

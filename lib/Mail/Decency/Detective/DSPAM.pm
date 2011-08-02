package Mail::Decency::Detective::DSPAM;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;
with qw/
    Mail::Decency::Detective::Core::Spam
    Mail::Decency::Detective::Core::User
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Net::LMTP;
use Data::Dumper;
use MIME::Base64;
use Mail::Decency::Detective::Core::Constants;

=head1 NAME

Mail::Decency::Detective::DSPAM

=head1 DESCRIPTION

Uses LMTP to connect directly to running DSPAM server an retreive filter result

=head1 DSPAM CONFIG

You have to configure decency accordingly to the DSPAM settings. Modify in dspam.conf:

=over

=item * ServerPass.*

DSPAM:
    ServerPass.Relay1       "secret"

dececny:
    client_ident: 'secret@Relay1'

=item * ServerHost, ServerPort

DSPAM:
    ServerHost      127.0.0.1
    ServerPort      17000

decency:
    host: '127.0.0.1'
    port: 17000

=back

=head1 CLASS ATTRIBUTES

=head2 client_ident : Str

The DSPAM auth string, as set for ClientIdent in dspam.conf

Defaults: secret@Relay1

=cut

has client_ident => (
    is        => 'rw',
    isa       => 'Str',
    default   => 'secret@Relay1'
);

=head2 host : Str

Host string/ip where DSPAM runs

Default: 127.0.0.1

=cut

has host => (
    is      => 'rw',
    isa     => 'Str',
    default => '127.0.0.1'
);

=head2 port : Int

Port where DSPAM listens

Default: 1024

=cut

has port => (
    is      => 'rw',
    isa     => 'Int',
    default => 1024
);


=pod

Private variables

=cut

has mode_check => (
    is      => 'ro',
    isa     => 'Str',
    default => '--user %user% --client --classify --stdout'
);

has mode_learn_spam => (
    is      => 'ro',
    isa     => 'Str',
    default => '--client --user %user% --mode=teft --source=corpus --class=spam --deliver=spam --stdout'
);

has mode_unlearn_spam => (
    is      => 'ro',
    isa     => 'Str',
    default => '--client --user %user% --mode=toe --source=corpus --class=innocent --deliver=innocent --stdout'
);

has mode_learn_ham => (
    is      => 'ro',
    isa     => 'Str',
    default => '--client --user %user% --mode=teft --source=corpus --class=innocent --deliver=innocent --stdout'
);

has mode_unlearn_ham => (
    is      => 'ro',
    isa     => 'Str',
    default => '--client --user %user% --mode=toe --source=corpus --class=spam --deliver=spam --stdout'
);

=head1 METHODS


=head2 init

=cut

sub init {
    shift->add_config_params( qw/ client_ident host port / );
}

=head2 handle

Pipeps mails through DSPAM server, retreives result

=cut


sub handle {
    my ( $self ) = @_;
    
    # get result from dspam
    my $result = $self->retreive_result( 'check' );
    
    # no result -> do not bother
    return unless $result;
    
    $self->logger->debug2( "DSPAM result: '$result'" );
    
    # oops, wrong client_ident
    if ( $result =~ /Need MAIL FROM here/ ) {
        $self->logger->error( "Wrong auth credentials for DSPAM. Please set client_ident the same as your ServerPass.* in dspam.conf" );
        return ;
    }
    
    # parse result
    my %parsed = map {
        my ( $n, $v ) = split( /\s*[:=]\s*/, $_, 2 );
        $v =~ s/^"//;
        $v =~ s/"$//;
        ( $n => lc( $v ) );
    } split( /\s*;\s*/, $result );
    
    # get weighting
    my $weight = 0;
    my @info = ();
    if ( $parsed{ result } eq 'innocent' ) {
        $weight = $self->weight_innocent;
    }
    elsif ( $parsed{ result } eq 'spam' ) {
        $weight = $self->weight_spam;
    }
    $self->logger->debug0( "Score mail to '$weight'" );
    
    # add info for noisy headers
    push @info, (
        "DSPAM result: $parsed{ result }",
        "DSPAM confidence: $parsed{ confidence }",
        "DSPAM probability: $parsed{ probability }",
        "DSPAM class: $parsed{ class }",
    );
    
    # add weight to content filte score
    return $self->add_spam_score( $weight, \@info );
}


=head2 train

=cut

sub train {
    my ( $self, $mode ) = @_;
    
    DD::cop_it "Train mode has to be 'spam' or 'ham'\n"
        unless $mode eq 'spam' || $mode eq 'ham';
    
    my $result = $self->retreive_result( "learn_${mode}" );
    print "> R $result\n";
    return ( $result ? 1 : 0, $result, $result ? 0 : 1 );
}


=head2 retreive_result

Pass mail via L<Net::LMTP> to DSPAM an retreive result

=cut

sub retreive_result {
    my ( $self, $mode ) = @_;
    
    # determine mode
    my $mode_method = "mode_${mode}";
    DD::cop_it "Cannot use mode '$mode'. Not defined!\n"
        unless $self->can( $mode_method );
    my $mode_cmd = $self->$mode_method;
    
    # determine user for mode
    if ( $mode_cmd =~ /%user%/ ) {
        my $user = $self->get_user();
        $mode_cmd =~ s/%user%/$user/g;
    }
    
    
    # determine timeout
    my $timeout = $self->timeout - 1;
    $timeout = 300 if $timeout <= 0;
    
    # connect via lmtp
    my $lmtp;
    eval {
        $lmtp = Net::LMTP->new(
            $self->host, $self->port,
            Timeout => $timeout,
            Helo => 'decency',
            Debug => $ENV{ DEBUG_DSPAM } || 0
        );
    };
    
    # error in connection
    if ( $@ ) {
        $self->logger->error( "Error connecting to dspam (". $self->host. ":". $self->port. "): $@" );
        return;
    }
    elsif ( ! $lmtp ) {
        $self->logger->error( "Could not connect to dspam (". $self->host. ":". $self->port. "): $@" );
        return ;
    }
    
    # send hello, authentify
    $lmtp->_MAIL( "FROM: <". $self->client_ident. "> DSPAMPROCESSMODE=\"$mode_cmd\"" );
    
    # send mail
    $lmtp->data;
    
    # retreive check result (maybe dspam refuses)
    my ( $check ) = $lmtp->message;
    if ( $check && $check =~ /DSPAM agent misconfigured:/ ) {
        $self->logger->error( "Error communicating with DSPAM: $check" );
        return ;
    }
    
    # write data to dspam
    my $fh = $self->open_file( '<', $self->file );
    while ( my $l = <$fh> ) {
        chomp $l;
        $lmtp->datasend( $l. CRLF );
    }
    close $fh; 
    $lmtp->dataend;
    
    # retreive result
    my ( $result ) = $lmtp->getline;
    chomp( $result );
    
    # quit
    $lmtp->quit;
    
    return $result;
}


=head1 SEE ALSO

=over

=item * L<Mail::Decency::Detective::Core::Cmd>

=item * L<Mail::Decency::Detective::Core::Spam>

=item * L<Mail::Decency::Detective::Bogofilter>

=item * L<Mail::Decency::Detective::CRM114>


=back

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

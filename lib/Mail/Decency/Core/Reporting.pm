package Mail::Decency::Core::Reporting;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use mro 'c3';
use Data::Dumper;
use File::Basename qw/ dirname /;
use Sys::Syslog qw/ :standard :macros /;

=head1 NAME

Mail::Decency::Detective::Reporting

=head1 DESCRIPTION

Reporting for mail throughput. Writes log files of rejected and throughputted mails for
later analyse or user presentation.

=head2 LOG FORMAT

The format is CSV in the form:

    <time>\t<server>\t<from>\t<to>\t<size>\t<status>\t<info>

=over

=item * time

Unix timestamp

=item * server

Either p for Doorman (policy server) or c for Detective (content filter)

=item * from, to

Sender and recipient

=item * size

Only in contnet filter: size in bytes

=item * status

There are several:

=over

=item * ongoing

Positive answer (mail not rejectd)

Aquivalent to DUNNO

=item * ok (Doorman)

Positive answer (mail not rejectd)

Accepted

=item * prepend (Doorman)

Positive answer (mail not rejectd)

=item * spam

Mail is spam. In Doorman this means (depending on your configuration) rejected. In Detective, this can mean either deleted or delivererd.

=item * virus (Detective)

Mail is marked as virus. Probably deleted or quarantained

=item * drop (Detective)

A module (eg Archive) decided to drop the mail silently

=back

=item * info

This string contains detailed information of the filtering. Each module's information is seperated by "##" and looks kind of:

    1298587714	p	from@sender.tld	to@recipient.tld	0	spam	Module: DNSBL; Score: 0; No hit on DNSBLs ## Module: Basic; Score: -100; Helo hostname is not in FQDN

=back


=head2 OUTPUT DESTINATIONS

You can either report to a file (which is save to rotate) or via syslog.


=head1 CONFIG

In serve config

    ---
    
    reporting:
        file: /path/to/file
        disabled_accepted: 1
        syslog: 1

=head1 CLASS ATTRIBUTES

=head2 reporting_enabled : Bool

Wheter enabled or not

Default: 0

=cut

has reporting_enabled => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 reporting_accepted_disabled : Bool

Wheter reporting of accepted mails is enabled (helpful if you use
multiple servers and dont want to log accepted mails, but in the
last server)

=cut

has reporting_accepted_disabled => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 reporting_file : Str

Path to output reporting file

Default: 

=cut

has reporting_file => ( is => 'rw', isa => 'Str' );

=head2 _reporting_methods : ArrayRef[SubRef]

=cut

has _reporting_methods => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

=head1 METHODS

=head2 after init

=cut

after init => sub {
    my ( $self ) = @_;
    
    my $reporting_ref = $self->config->{ reporting } || {};
    my @log_methods;
    
    if ( my $file = $reporting_ref->{ file } ) {
        my $dir = dirname( $file );
        DD::cop_it "Reporting: Create directory '$dir', or we cannot use file '$file' for logging\n"
            unless -d $dir;
        $self->reporting_file( $file );
        push @log_methods, \&_reporting_log_file;
    }
    
    if ( $reporting_ref->{ syslog } ) {
        openlog( "decency", "ndelay,pid", "local0" );
        push @log_methods, \&_reporting_log_syslog;
    }
    
    if ( @log_methods ) {
        $self->reporting_enabled( 1 );
        $self->reporting_accepted_disabled( 1 )
            if $reporting_ref->{ disabled_accepted };
        $self->set_locker( 'reporting', timeout => 3 );
        $self->_reporting_methods( \@log_methods );
        
        # $self->register_hook( post_finish => sub {
        #     my ( $server, $attrs_ref ) = @_;
        #     $server->write_report( $attrs_ref );
        # } );
        # $self->register_hook( finish => sub {
        #     my ( $server, $attrs_ref ) = @_;
        #     $server->write_report( $attrs_ref );
        # } );
    }
    
    return ;
};

=head2 write_report

Writes report to report log

=cut

sub write_report {
    my ( $self, $status, $spam_details ) = @_;
    
    # stop if not required
    return if $self->reporting_accepted_disabled
        && $status =~ /^(?:ongoing|prepend|ok)$/;
    my $server_prefix = lc( $self->name ) =~ /detective/ ? 'c' : 'p';
    
    # build row
    my @row;
    my $session = $self->session;
    push @row, time();
    push @row, $session->identifier;
    push @row, $server_prefix;
    push @row, $session->from;
    push @row, $session->to;
    push @row, $session->can( 'file_size' ) ? $session->file_size : 0;
    push @row, $status;
    push @row, $spam_details;
    
    my $msg = join( "\t", map { s/[\t\n\r]//gms; $_ } @row );
    $self->$_( $msg ) for @{ $self->_reporting_methods };
    
    return ;
}

=head2 _reporting_log_file

=cut

sub _reporting_log_file {
    my ( $self, $msg ) = @_;
    
    # get lock
    $self->usr_lock( 'reporting' );
    
    # write
    my $fh;
    eval {
        my $file = $self->reporting_file;
        my $mode = -f $file ? '>>' : '>';
        open $fh, $mode, $file
            or DD::cop_it "Cannot open reporting file '". $file. "' for write/append: $!";
        print $fh "$msg\n";
    };
    $self->logger->error( "Error in reporting: $@" ) if $@;
    close $fh if $fh;
    
    # unlock
    $self->usr_unlock( 'reporting' );
}


=head2 _reporting_log_syslog

=cut

sub _reporting_log_syslog {
    my ( $self, $msg ) = @_;
    syslog( LOG_INFO, "REPORT: $msg" );
}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

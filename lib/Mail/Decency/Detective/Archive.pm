package Mail::Decency::Detective::Archive;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
    Mail::Decency::Detective::Model::Archive
/;
use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use File::Path qw/ mkpath /;
use File::Basename qw/ fileparse /;
use File::Copy qw/ copy /;
use Mail::Decency::Core::Exception;
use Digest::MD5;
use IO::File;

=head1 NAME

Mail::Decency::Detective::Archive

=head1 DESCRIPTION

Archive module. Write a copy of the passing mail to archive directory on disk.

=head1 CONFIG

    ---
    
    disable: 0
    
    # possible variables are:
    #   * recipient_domain .. eg recipient.tld
    #   * recipient_prefix .. eg username
    #   * recipient_address .. eg username@recipient.tld
    #   * sender_domain .. eg senderdomain.tld
    #   * sender_prefix .. eg sender
    #   * sender_address .. eg sender@senderdomain.tld
    #   * ymd .. eg 2010-05-24
    #   * hm  .. eg 21-26 (= 21:26h)
    archive_dir: '/var/archive/%recipient_domain%/%recipient_prefix%/%ymd%/%hm%/'
    #archive_dir: '/var/archive/%ymd%/%recipient_domain%/%recipient_prefix%'
    
    # wheter archive also mails recognized as spam
    archive_spam: 1
    
    # wheter to drop the mail after archiving .. means: will not be
    #   reinjected for delivery.
    drop: 0
    
    # wheter use index database or not
    use_index_db: 1
    
    # wheter also use the full text index
    enable_full_text_index: 1
    

=head1 SQL

For the search index

    -- TABLE: archive_index (SQLITE):
    CREATE TABLE ARCHIVE_INDEX ("search" text, "from_domain" varchar(255),
        "subject" varchar(255), "from_prefix" varchar(255), "created" int,
        "to_domain" varchar(255), "to_prefix" varchar(255), "filename" text,
        "md5" varchar(32), id INTEGER PRIMARY KEY);
    CREATE INDEX ARCHIVE_INDEX_CREATED ON ARCHIVE_INDEX ("created");
    CREATE INDEX ARCHIVE_INDEX_SUBJECT ON ARCHIVE_INDEX ("subject");
    CREATE INDEX ARCHIVE_INDEX_FROM_DOMAIN_FROM_PREFIX ON ARCHIVE_INDEX
        ("from_domain", "from_prefix");
    CREATE INDEX ARCHIVE_INDEX_TO_DOMAIN_TO_PREFIX ON ARCHIVE_INDEX
        ("to_domain", "to_prefix");

=head1 CLASS ATTRIBUTES


=head2 archive_dir : Str

Archive directory where the mails are stored in.

=cut

has archive_dir => ( is => 'rw', isa => 'Str' );

=head2 drop : Bool

If true, drop mails after archiving (do not forward them). For an "archive only" kind of server.

Default: 0

=cut

has drop => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 archive_spam : Bool

Do archive mails, even if they are recognized as spam

Default: 0

=cut

has archive_spam => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 use_index_db : Bool

Wheter the index database shall be used or not. As all datbase access, potential slow-down. Useful if you want to use the API to search the archived mails by from, to or subject.

Default: 0

=cut

has use_index_db => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 enable_full_text_index : Bool

If database is enabled, this enables a lexer, which parses all text (text/plain, text/html) MIME parts of the mail and writes them into the "search" column of the archive databases.

Default: 0

=cut

has enable_full_text_index => ( is => 'rw', isa => 'Bool', default => 0 );


=head1 METHODS


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    $self->add_config_params( qw/
        drop archive_dir archive_spam use_index_db enable_full_text_index / );
    die "Require 'archive_dir' (full path for saving mails)\n"
        unless $self->config->{ archive_dir };
}


=head2 handle

Archive file into archive folder

=cut


sub handle {
    my ( $self ) = @_;
    
    $self->session->set_flag( 'archived' );
    
    # perform archive
    my $file = $self->archive_mail();
    
    # wheter use database or not
    if ( $self->use_index_db ) {
        my $session = $self->session;
        my $mime = $session->mime;
        my $head = $mime->head;
        chomp( my $subject = substr( $head->get( 'Subject' ), 0, 255 ) );
        my %create = (
            created     => time(),
            subject     => $subject,
            to_domain   => $session->to_domain,
            to_prefix   => $session->to_prefix,
            from_domain => $session->from_domain,
            from_prefix => $session->from_prefix,
            filename    => $file
        );
        
        # get md5
        my $md5 = Digest::MD5->new;
        my $fh = $self->open_file( '<', $file );
        $md5->addfile( $fh );
        $create{ md5 } = $md5->hexdigest;
        close $fh;
        
        # also use full text index ?
        if ( $self->enable_full_text_index ) {
            my %token;
            
            my $sub_get_content = sub {
                my ( $mime, $n ) = @_;
                return $mime->get( 'Content-Type' ) =~ /^text\/(?:plain|html)(?:$|;)/
                    ? ( $mime )
                    : ( map { $n->( $_ ) } $mime->parts )
                ;
            };
            
            my @parts = $sub_get_content->( $mime, $sub_get_content );
            foreach my $part( @parts ) {
                my $body = $part->get( 'Content-Type' ) =~ /^text\/plain/
                    ? $part->stringify_body
                    : do {
                        my $b = $part->stringify_body;
                        $b =~ s/<.+?>//gms;
                        $b =~ s/&\w+;//gms;
                        $b;
                    }
                ;
                $token{ $_ } ++ for grep {
                    length($_) > 2
                } map {
                    s/[^\p{L}_-]//gms;
                    s/([-_*])(\w+)\1/$2/gms;
                    $_;
                } split( ' ', lc( $body ) );
            }
            $create{ search } = join( ' ', sort keys %token );
        }
        
        # write to index database
        $self->database->set( archive => index => \%create );
    }
    
    # die here with drop exception, if don't want to keep
    Mail::Decency::Core::Exception::Drop->throw( { message => "Drop after archive" } )
        if $self->drop;
    
    return ;
}


=head2 archive_mail

Write mail to archive directory.

=cut

sub archive_mail {
    my ( $self ) = @_;
    
    # get directory, split into file and dir path
    my ( $file, $dir ) = fileparse( $self->build_dir );
    $file ||= "mail";
    
    # try make directory, die on error
    mkpath( $dir, { mode => 0700 } ) unless -d $dir;
    die "Could not create archive directory '$dir'" unless -d $dir;
    
    # make a temp file within (assure it is unique)
    my ( $th, $full_path )
        = $self->get_static_file( $dir, $file. "-". time(). "-XXXXXX", SUFFIX => '.eml' );
    $self->close_file( $th );
    
    # copy actual file to archive folder
    copy( $self->file, $full_path );
    $self->logger->debug0( "Stored mail in '$full_path' ". ( -f $full_path ? "OK" : "ERROR" ) );
    
    return $full_path;
}


=head2 build_dir

Builds dir based on variables.

=cut

sub build_dir {
    my ( $self ) = @_;
    
    my $dir = $self->archive_dir;
    
    # parse recipient_*
    if ( $dir =~ /\%recipient/ ) {
        my $recipient_address = $self->normalize_str( $self->to || "unknown\@unknown" );
        my ( $recipient_prefix, $recipient_domain ) = split( /@/, $recipient_address, 2 );
        $recipient_prefix ||= "unknown";
        $recipient_domain ||= "unknown";
        $dir =~ s/\%recipient_address\%/$recipient_address/g;
        $dir =~ s/\%recipient_prefix\%/$recipient_prefix/g;
        $dir =~ s/\%recipient_domain\%/$recipient_domain/g;
    }
    
    # parse sender_*
    if ( $dir =~ /\%sender/ ) {
        my $sender_address = $self->normalize_str( $self->from || "unknown\@unknown" );
        my ( $sender_prefix, $sender_domain ) = split( /@/, $sender_address, 2 );
        $sender_prefix ||= "unknown";
        $sender_domain ||= "unknown";
        $dir =~ s/\%sender_address\%/$sender_address/g;
        $dir =~ s/\%sender_prefix\%/$sender_prefix/g;
        $dir =~ s/\%sender_domain\%/$sender_domain/g;
    }
    
    # parse time
    if ( $dir =~ /\%(ymd|hm)\%/ ) {
        my @date = localtime(); # 0: sec, 1: min, 2: hour, 3: day, 4: month, 5: year
        $date[4]++;
        $date[5] += 1900;
        
        my $ymd = sprintf( '%04d-%02d-%02d', @date[ 5, 4, 3 ] );
        my $hm  = sprintf( '%02d-%02d', @date[ 2, 1 ] );
        
        $dir =~ s/\%ymd\%/$ymd/g;
        $dir =~ s/\%hm\%/$hm/g;
    }
    
    # cleanup dir
    $dir =~ s#//+#/#g;
    
    return $dir;
}


=head2 normalize_str

Replace not allowed characters ..

=cut

sub normalize_str {
    my ( $self, $str ) = @_;
    $str =~ s/[^\p{L}\d\-_\.@\+]/_/gms;
    $str =~ s/__/_/g;
    return lc( $str );
}

=head2 hook_post_finish

Grep mails, even if they are spam, if archive_spam is enabled

=cut

sub hook_post_finish {
    my ( $self, $state, $exit_code ) = @_;
    
    # do archive mail ..
    $self->archive_mail()
        if ! $self->session->has_flag( 'archived' )
        && $state eq 'spam'
        && $self->archive_spam;
    
    return ( $state, $exit_code );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

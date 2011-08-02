package Mail::Decency::Core::SessionItem::Detective;

use Mouse;
extends qw/
    Mail::Decency::Core::SessionItem
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use MIME::Parser;
use IO::File;
use YAML;
use Data::Dumper;
use Regexp::Common qw/ net /;
use Regexp::IPv6 qw/ $IPv6_re /;
use Mail::Field::Received;

=head1 NAME

Mail::Decency::Core::SessionItem::Detective

=head1 DESCRIPTION

The id attribute is the current QUEUE ID

=head1 CLASS ATTRIBUTES

=head2 file

The file (in the spool folder, absolute path)

=cut

has file => ( is => 'ro', isa => "Str", required => 1, trigger => \&_init_file );

=head2 store

YAML file containing the current mime/mail/file info

=cut

has store => ( is => 'rw', isa => "Str" );

=head2 file_size

Size of the current file (id)

=cut

has file_size => ( is => 'rw', isa => "Int", default => 0 );

=head2 virus

String containg info (name) of the virus

=cut

has virus => ( is => 'rw', isa => "Str" );

=head2 next_id

If set, we now of the next queue id

=cut

has next_id => ( is => 'rw', isa => "Str" );

=head2 prev_id

If set, we now of the previous queue id

=cut

has prev_id => ( is => 'rw', isa => "Str" );

=head2 mime_output_dir

The directory where mime files are to be output (from Detective)

=cut

has mime_output_dir => ( is => 'rw', isa => "Str", required => 1 );

=head2 mime

Is a MIME::Entity object representing the current mail

=cut

has mime => ( is => 'rw', isa => "MIME::Entity" );

=head2 mime_filer

The filer used for cleanup

=cut

has mime_filer => ( is => 'rw', isa => "MIME::Parser::FileUnder" );

=head2 mime_header_changes

Tracks changs in MIME headers

=cut

has mime_header_changes => ( is => 'rw', isa => "HashRef", default => sub {{}} );

=head2 mime_fh

File handle for mime file

=cut

has mime_fh => ( is => 'rw', isa => "IO::File" );

=head2 verify_key

Instance of L<Crypt::OpenSSL::RSA> representing the forward sign key

=cut

has verify_key => ( is => 'rw', isa => 'Crypt::OpenSSL::RSA', predicate => 'can_verify' );


=head2 verify_ttl

TTL for validity of signatures in seconds

=cut

has verify_ttl => ( is => 'rw', isa => 'Int', predicate => 'has_verify_ttl' );

=head2 ips : ArrayRef[Str]

Ip addresses from the Received-header. All LAN or localhost addresses are filtered out.

=cut

has ips => (
    is      => 'rw',
    isa     => 'ArrayRef[Str]',
    default => sub { [] }
);

=head2 _mime_changed : Bool

Contains value wheter MIME has hcanaged

=cut

has _mime_changed => (
    is      => 'rw',
    isa     => "Bool",
    traits  => [ 'MouseX::NativeTraits::Bool' ],
    default => 0,
    handles => {
        mime_has_changed => 'set',
        mime_written     => 'unset'
    }
);


=head2 disable_reinject

Can be set either by modules or for example by milter from Defender

=cut

has disable_reinject => ( is => 'rw', isa => 'Bool', default => 0 );


=head1 METHODS

=head2 mime_has_changed

Announces that the MIME file has changed

=head2 mime_written

Announces that the MIME file has been written and is up2date

=head2 write_mime 

Update the file ($self->file) from mime .. should be performed after
mime manipulations

=cut

sub write_mime {
    my ( $self ) = @_;
    
    # get mime object
    my $mime = $self->mime;
    
    # resync file size
    $mime->sync_headers( Length => 'COMPUTE' );
    
    # store backup fore failure recovery
    my $tmp_name = $self->file. ".$$.". time();
    rename( $self->file, $tmp_name );
    
    # write back to file
    eval {
        unlink( $self->file );
        open my $fh, '>', $self->file;
        $mime->print( $fh );
        close $fh;
    };
    
    # restore backup on error
    if ( $@ ) {
        rename( $tmp_name, $self->file );
        return 0;
    }
    else {
        $self->file_size( -s $self->file );
        unlink( $tmp_name );
    }
    
    return 1;
}

=head2 mime_header

Modify header, announces changes

    $self->session->mime_header( add => HeaderName => 'value' );
    $self->session->mime_header( modify => HeaderName => 'value' );

=cut

sub mime_header {
    my ( $self, $meth, $header, @value ) = @_;
    return $self->mime->head unless $meth;
    $self->mime_header_changes->{ $meth } ||= {};
    push @{ $self->mime_header_changes->{ $meth }->{ $header } ||= [] }, @value;
    $self->mime_has_changed();
    return $self->mime->head->$meth( $header, @value );
}


=head2 update_store 

Write store YAML file

=cut

sub update_store {
    my ( $self ) = @_;
    open my $fh, '>', $self->store
        or DD::cop_it "Cannot open store file ". $self->store. " for write: $!";
    my %create = ();
    $create{ from } = $self->from if $self->from;
    $create{ to } = $self->to if $self->to;
    print $fh YAML::Dump( {
        file => $self->file,
        size => $self->file_size,
        %create
    } );
    close $fh;
}


=head2 update_from_doorman_cache 

Update session from cached doorman session

=cut

sub update_from_doorman_cache {
    my ( $self, $hash_ref ) = @_;
    
    # update spam score
    $self->spam_score( $self->spam_score + $hash_ref->{ spam_score } )
        if $hash_ref->{ spam_score };
    
    # update spam details
    push @{ $self->spam_details }, @{ $hash_ref->{ spam_details } }
        if $hash_ref->{ spam_details };
    
    # update spam details
    if ( $hash_ref->{ flags } ) {
        $self->set_flag( $_ ) for keys %{ $hash_ref->{ flags } };
    }
    
    return;
}


=head2 update_from_cache 

Update session from cached session

=cut

sub update_from_cache {
    my ( $self, $hash_ref ) = @_;
    
    $self->update_from_doorman_cache( $hash_ref );
    
    $self->virus( join( "; ", $self->virus, $hash_ref->{ virus } ) )
        if $hash_ref->{ virus };
    
    foreach my $id( qw/ next_id prev_id / ) {
        $self->$id( $hash_ref->{ $id } )
            if ! $self->$id && $hash_ref->{ $id };
    }
    
    return;
}



=head2 for_cache

returns data formatted for cache

=cut

sub for_cache {
    my ( $self ) = @_;
    
    return {
        spam_score   => $self->spam_score,
        spam_details => $self->spam_details,
        virus        => $self->virus,
        queue_id     => $self->id,
        next_id      => $self->next_id,
        prev_id      => $self->prev_id,
        identifier   => $self->identifier
    };
}


=head2 cleanup

Called at the end of the session.. removes all temp files and the mail file

=cut

sub cleanup {
    my ( $self ) = @_;
    
    # close mime handle
    eval { $self->mime_fh->close }; # do silent, don't care for errors
    
    # clear mime
    eval { $self->mime_filer->purge; };
    warn "Error in purge: $@\n" if $@;
    
    # remove store file
    unlink $self->store
        if $self->store && -f $self->store;
    
    # remove store file
    unlink $self->file
        if $self->file && -f $self->file;
    
    $self->mime_header_changes( {} );
    
    $self->unset;
    
    return ;
}


=head2 retreive_doorman_scoring

=cut

sub retreive_doorman_scoring {
    my ( $self, $accept_scoring ) = @_;
    
    # having decency instance (from doorman) ?
    my @instance = map {
        chomp;
        my ( $instance, $signature, $weight, $timestamp, $flags, @info ) = split( /\|/, $_ );
        [ $instance, $signature, $weight, $timestamp, $flags, @info ];
    } $self->mime->head->get( 'X-Decency-Instance' );
    
    # remember wheter cleanup is required
    my $cleanup_instance = scalar @instance > 0;
    
    # using signed forwarded info ? (bother only if scoring from external is accepted!)
    if ( @instance && $accept_scoring && $self->can_verify ) {
        
        # get all valid instances
        @instance = grep {
            my ( $instance, $signature, $weight, $timestamp, $flags, @info ) = @$_;
            
            # verify instance
            my $ok = $self->verify_key->verify(
                join( "|", $instance, $weight, $timestamp, $flags, @info ),
                pack( "H*", $signature )
            );
            
            # valid ?
            $ok && $timestamp <= time() && ( ! $self->has_verify_ttl || $timestamp + $self->verify_ttl >= time() );
        } @instance;
    }
    
    # having any instances ?
    if ( @instance ) {
        
        # handle first instance
        #   this is the LATEST instance.. contains the FINAL score
        my $first_ref = shift @instance;
        my ( $instance, $keyword, $weight, $timestamp, $flags, @info ) = @$first_ref;
        
        # try read from cache
        #   if Doorman and Detective use the same cache, this will hit!
        my $cached = $self->cache->get( "DOORMAN-$instance" );
        if ( $cached ) {
            
            # remove Doorman finally from cache..
            #   there are no Doorman behind the Detective ..
            $self->cache->remove( "DOORMAN-$instance" );
            
            # add spam score, details
            $self->update_from_doorman_cache( $cached );
        }
        
        # not from cache
        #   if Doorman accepts scorings in the first place ..
        elsif ( $accept_scoring ) {
            
            # init for update ..
            #   only the first weight will be used, because it is the last
            #   policy weight and therfore the cumulated policy weight
            $cached= {
                spam_score   => $weight,
                spam_details => \@info,
                flags        => { map { ( $_ => 1 ) } split( /\s*,\s*/, $flags ) }
            };
            
            # get flags and info from older instances
            foreach my $older_instance( @instance ) {
                ( undef, undef, undef, undef, my $add_flags, my @add_info )
                    = split( /\|/, $instance );
                push @{ $cached->{ spam_details } }, @add_info;
                $cached->{ flags }->{ $_ } = 1 for split( /\s*,\s*/, $add_flags );
            }
            
            # add spam score, details
            $self->update_from_doorman_cache( $cached );
        }
    }
    
    # cleanup instances ?
    if ( $cleanup_instance ) {
        $self->mime->head->delete( 'X-Decency-Instance' );
        $self->write_mime();
    }
}

=head2 current_file

Returns the current file. Performs write of changed mime data beforehand, if changed.

Modules shall use this instead of directly accessing 'file' 

=cut

sub current_file {
    my ( $self ) = @_;
    if ( $self->_mime_changed ) {
        $self->write_mime;
        $self->mime_written;
    }
    return $self->file;
}

=pod

PRIVATE METHODS

=pod

_init_file

Triggerd on file set

=cut

sub _init_file {
    my ( $self ) = @_;
    
    DD::cop_it "Cannot access file '". $self->file. "'" unless -f $self->file;
    $self->file_size( -s $self->file );
    
    # store
    $self->store( $self->file. '.info' );
    my $has_store = 0;
    if ( -f $self->store ) {
        $has_store++;
        my $ref;
        eval {
            $ref = YAML::LoadFile( $self->store );
        };
        DD::cop_it "Error loading YAML file ". $self->store. ": $@" if $@;
        DD::cop_it "YAML file ". $self->store. " mal formatted, should be HASH, is '". ref( $ref ). "'"
            unless ref( $ref ) eq 'HASH';
        
        foreach my $attr( qw/ from to / ) {
            $self->$attr( $ref->{ $attr } ) unless $self->$attr;
        }
    }
    
    # setup mime
    my $parser = MIME::Parser->new;
    $parser->output_under( $self->mime_output_dir );
    
    #$parser->decode_headers( 1 ); # << THIS MADE DKIM IMPOSSIBLE <<
    
    # read from file and create
    my $orig_fh = IO::File->new( $self->file, 'r' )
        or DD::cop_it "Cannot open ". $self->file. " for read\n";
    
    eval {
        my $mime = $parser->parse( $orig_fh );
        $self->mime( $mime );
        $self->mime_filer( $parser->filer );
        $self->mime_fh( $orig_fh );
    };
    DD::cop_it "Error parsing MIME: $@\n" if $@;
    
    # get mime header shorthcut
    my $mime_head = $self->mime->head;
    
    # extract relevant headers ..
    unless ( $self->to ) {
        my $to = "". ( $mime_head->get( 'Delivered-To' ) ||  $mime_head->get( 'To' )  || "" );
        if ( $to ) {
            if ( $to =~ /<([^>]+)>/ ) {
                $to = $1;
            }
            1 while chomp( $to );
            $self->to( $to );
        }
    }
    
    # extact from..
    unless ( $self->from ) {
        my $from = "". ( $mime_head->get( 'Return-Path' ) ||  $mime_head->get( 'From' ) || "" );
        if ( $from ) {
            if ( $from =~ /<([^>]+)>/ ) {
                $from = $1;
            }
            1 while chomp( $from );
            $self->from( $from );
        }
    }
    
    #
    # <<<< @@@@@@@HERE@@@@@@@@
    #   add ip attribute from Received-header
    # <<<< @@@@@@@HERE@@@@@@@@
    #
    my @received = $mime_head->get( 'Received' );
    my ( @received_ips, %received_ip_seen );
    foreach my $received( @received ) {
        
        # get header
        my $header = Mail::Field::Received->new( Received => $received );
        
        # get tree
        my $tree_ref = eval { $header->parse_tree() };
        
        # no address ..
        next unless $tree_ref
            && defined $tree_ref->{ from }
            && defined $tree_ref->{ from }->{ address };
        
        # get address
        my $address = $tree_ref->{ from }->{ address };
        
        # seen ?
        next if $received_ip_seen{ $address }++;
        
        #print Dumper( $header->parse_tree() );
        push @received_ips, $address
            unless $address =~ /^(?:127|10|192\.168|172\.16|)\./
            || $address =~ /^(?:f[cdef]|(?:0{1,4}:){7}0{0,3}1)/;
    }
    $self->ips( \@received_ips ) if @received_ips;
    
    # write relevant info to store file
    $self->update_store() unless $has_store;
}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;

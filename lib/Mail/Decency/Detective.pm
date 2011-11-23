package Mail::Decency::Detective;

use Mouse;
extends qw/
    Mail::Decency::Core::Server
/;

with qw/
    Mail::Decency::Core::Stats
    Mail::Decency::Core::DatabaseCreate
    Mail::Decency::Core::Excludes
    Mail::Decency::Core::CustomScoring
    Mail::Decency::Core::Reporting
/;

use version 0.74; our $VERSION = qv( "v0.1.7" );

use feature qw/ switch /;

use Data::Dumper;
use Scalar::Util qw/ weaken blessed /;
use YAML;
use MIME::Parser;
use MIME::Lite;
use IO::File;
use File::Path qw/ mkpath /;
use File::Copy qw/ copy move /;
use File::Temp qw/ tempfile /;
use Cwd qw/ abs_path /;
use Crypt::OpenSSL::RSA;
use Time::HiRes qw/ tv_interval gettimeofday /;
use Mail::Decency::Helper::Config qw/
    merged_config
/;

use Mail::Decency::Helper::Debug;
use Mail::Decency::Detective::Core::Constants;
use Mail::Decency::Core::SessionItem::Detective;
use Mail::Decency::Core::NetServer::SMTPDetective;
use Mail::Decency::Core::Exception;

=head1 NAME

Mail::Decency::Detective

=head1 SYNOPSIS

    use Mail::Decency::Detective;
    
    my $detective = Mail::Decency::Detective->new( {
        config => '/etc/decency/detective.yml'
    } );
    
    $detective->run;

=head1 DESCRIPTION

L<www.decency-antispam.org/docs/detective>

=head1 CLASS ATTRIBUTES


=head2 spool_dir : Str

The directory where to save received mails before filtering

=cut

has spool_dir => ( is => 'rw', isa => 'Str' );

=head2 temp_dir : Str

Holds temp files for modules

=cut

has temp_dir => ( is => 'rw', isa => 'Str' );

=head2 queue_dir : Str

Holds queued mails (currently working on)

=cut

has queue_dir => ( is => 'rw', isa => 'Str' );

=head2 mime_output_dir : Str

Directory for temporary mime output .. required by MIME::Parser

Defaults to spool_dir/mime

=cut

has mime_output_dir => ( is => 'rw', isa => 'Str' );

=head2 reinject_failure_dir : Str

Directory for reinjection failures

Defaults to spool_dir/failure

=cut

has reinject_failure_dir => ( is => 'rw', isa => 'Str' );

=head2 bounce_on_reinject_failure : Bool

Whether to bounce if a reinjection failed.

Default: 0 (disabled, do not bounce)

=cut

has bounce_on_reinject_failure => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 quarantine_dir : Str

Directory for quarantined mails (virus, spam)

Defaults to spool_dir/quarantine

=cut

has quarantine_dir => ( is => 'rw', isa => 'Str' );

=head2 spam_*

There is either spam scoring, strict or keep.

Keep account on positive or negative score per file. Each filter module may increment or decrement score on handling the file. The overall score determines in the end wheter to bounce or re-inject the mail.

=head3 spam_behavior : Str

How to determine what is spam. Either scoring, strict or ignore

Default: scoring

=cut

has spam_behavior => ( is => 'rw', isa => 'Str', default => 'scoring' );

=head3 spam_handle : Str

What to do with recognized spam. Either tag, bounce or delete

Default: tag

=cut

has spam_handle => ( is => 'rw', isa => 'Str', default => 'tag' );

=head3 spam_subject_prefix : Str

If spam_handle is tag: "Subject"-Attribute prefix for recognized SPAM mails.

=cut

has spam_subject_prefix => ( is => 'rw', isa => 'Str', predicate => 'has_spam_subject_prefix' );

=head3 spam_threshold : Int

For spam_behavior: scoring. Each cann add/remove a score for the filtered mail. SPAM scores are negative, HAM scores positive. If this threshold is reached, the mail is considered SPAM.

Default: -100

=cut

has spam_threshold => ( is => 'rw', isa => 'Int', default => -100 );

=head3 spam_notify_recipient : Bool

If enabled -> send recipient notification if SPAM is recognized.

Default: 0

=cut

has spam_notify_recipient => ( is => 'rw', isa => 'Bool', default => 0 );

=head3 spam_recipient_template : Str

Path to template used for SPAM notification.

=cut

has spam_recipient_template => ( is => 'rw', isa => 'Str' );

=head3 spam_recipient_subject : Str

Subject of the recipient's SPAM notification mail

Default: Spam detected

=cut

has spam_recipient_subject => ( is => 'rw', isa => 'Str', default => 'Spam detected' );

=head3 spam_noisy_headers : Bool

Wheter X-Decency headers in mail should contain detailed information.

Default: 0

=cut

has spam_noisy_headers => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 virus_*

Virus handling

=head3 virus_handle : Str

What to do with infected mails ? Either: bounce, delete or quarantine

Default: ignore

=cut

has virus_handle => ( is => 'rw', isa => 'Str', default => 'ignore' );

=head3 virus_notify_recipient : Bool

Wheter to notofy the recipient about infected mails.

Default: 0

=cut

has virus_notify_recipient => ( is => 'rw', isa => 'Bool', default => 0 );

=head3 virus_recipient_template : Str

Path to template used for recipient notification

=cut

has virus_recipient_template => ( is => 'rw', isa => 'Str' );

=head3 virus_recipient_subject : Str

Subject of the recipient's notification mail

Default: Virus detected

=cut

has virus_recipient_subject => ( is => 'rw', isa => 'Str', default => 'Virus detected' );

=head3 virus_notify_sender : Str

Wheter to notify the sender of an infected mail (NOT A GOOD IDEA: BACKSCATTER!)

Default: 0

=cut

has virus_notify_sender => ( is => 'rw', isa => 'Bool', default => 0 );

=head3 virus_sender_template : Str

Path to sender notification template

=cut

has virus_sender_template => ( is => 'rw', isa => 'Str' );

=head3 virus_sender_subject : Str

Subject of the sender notification

Default: Virus detected

=cut

has virus_sender_subject => ( is => 'rw', isa => 'Str', default => 'Virus detected' );


=head2 accept_scoring : Bool

Wheter to accept scoring from (external) Doorman.

Default: 0

=cut

has accept_scoring => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 doorman_verify_key : Str

Path to public (verification) key for scoring verification

Default: 0

=cut

has doorman_verify_key => ( is => 'rw', isa => 'Str', predicate => 'has_doorman_verify_key', trigger => sub {
    my ( $self, $key_file ) = @_;
    
    # check file
    $key_file = $self->config_dir . "/$key_file"
        if $self->has_config_dir && ! -f $key_file;
    DD::cop_it "Could not access doorman_verify_key key file '$key_file'\n"
        unless -f $key_file;
    
    # read key
    open my $fh, '<', $key_file
        or DD::cop_it "Cannot open doorman_verify_key key file for read: $!\n";
    my $key_content = join( "", <$fh> );
    close $fh;
    
    # store key
    $self->doorman_verify_key_rsa( Crypt::OpenSSL::RSA->new_public_key( $key_content ) );
    $self->logger->info( "Setup verify key '$key_file'" );
    
    return;
} );

=head2 doorman_verify_key_rsa : Crypt::OpenSSL::RSA

Instance of verification key (L<Crypt::OpenSSL::RSA>)

=cut

has doorman_verify_key_rsa => ( is => 'rw', isa => 'Crypt::OpenSSL::RSA' );


=head2 session : Mail::Decency::Core::SessionItem::Detective

SessionItem (L<Mail::Decency::Core::SessionItem::Detective>) of the current handle file

=cut

has session => ( is => 'rw', isa => 'Mail::Decency::Core::SessionItem::Detective' );


=head2 notification_from : Str

Notification sender (from address)

Default: Postmaster <postmaster@localhost>

=cut

has notification_from => ( is => 'rw', isa => 'Str', default => 'Postmaster <postmaster@localhost>' );


=head2 reinjections : ArrayRef[HashRef]

List of reinjection hosts

=cut

has reinjections => ( is => 'rw', isa => 'ArrayRef[HashRef]', predicate => 'can_reinject' );


=head1 METHODS

=head2 init


=cut

sub init {
    my ( $self ) = @_;
    
    # check classes for reinjection
    if ( defined $self->config->{ reinject } ) {
        my $reinject_ref = ref( $self->config->{ reinject } ) eq 'ARRAY'
            ? $self->config->{ reinject }
            : [ $self->config->{ reinject } ]
        ;
        my %smtp_classes;
        foreach my $ref( @$reinject_ref ) {
            if ( $ref->{ ssl } ) {
                $smtp_classes{ "Net::SMTP::SSL" }++;
            }
            elsif ( $ref->{ tls } ) {
                $smtp_classes{ "Net::SMTP::TLS" }++;
            }
            else {
                $smtp_classes{ "Net::SMTP" }++;
            }
        }
        foreach my $class( keys %smtp_classes ) {
            eval "use $class; 1;"
                or DD::cop_it "Could not load $class: $@, required for reinjection (deactivate tls/ssl or install this module)\n";
        }
        
        $self->reinjections( $reinject_ref );
    }
    
    # init name
    $self->name( "detective" );
    
    # mark es inited
    $self->init_logger();
    $self->init_dirs();
}


sub setup {
    my ( $self ) = @_;
    
    return if $self->{ inited } ++;
    
    $self->init_cache();
    $self->init_database();
    $self->init_reloadable();
    
    return;
}

=head2 init_reloadable

=cut

sub init_reloadable {
    my ( $self ) = @_;
    
    $self->init_server_shared();
    
    # set from..
    $self->notification_from( $self->config->{ notification_from } )
        if $self->config->{ notification_from };
    
    # reinject failure behavior
    $self->bounce_on_reinject_failure( $self->config->{ bounce_on_reinject_failure } ? 1 : 0 );
    
    # having scoring ?
    if ( defined( my $virus_ref = $self->config->{ virus } ) && ref( $self->config->{ virus } ) ) {
        
        # what's the basic behavior ?
        DD::cop_it "behavior has to be set to 'ignore', 'scoring' or 'strict' in spam section\n"
            unless $virus_ref->{ handle }
            && $virus_ref->{ handle } =~ /^(?:bounce|delete|quarantine|ignore)$/
        ;
        $self->virus_handle( $virus_ref->{ handle } );
        
        # for bounce mode ..
        if ( $self->virus_handle =~ /^(?:bounce|delete|quarantine)$/ ) {
            
            # check for each direction ..
            foreach my $direction( qw/ sender recipient / ) {
                next if $direction eq 'sender' && $self->virus_handle eq 'bounce';
                
                # determine methods and parameter names
                my $template = "${direction}_template"; # sender_template
                my $template_meth = "virus_$template";  # virus_sender_template
                my $enable = "notify_${direction}";     # notify_sender
                my $enable_meth = "virus_$enable";      # virus_notify_sender
                
                # is enabled ?
                $self->$enable_meth( $virus_ref->{ $enable } ? 1 : 0 );
                
                # having custom template ?
                if ( $self->$enable_meth() && $virus_ref->{ $template } ) {
                    my $filename = -f $virus_ref->{ $template }
                        ? $virus_ref->{ $template }
                        : $self->config_dir. "/$virus_ref->{ $template }"
                    ;
                    DD::cop_it "Cant read from virus $template file '$filename'\n"
                        unless -f $filename;
                    
                    # template
                    $self->$template_meth( $filename );
                    
                    # subject
                    my $subject = "${direction}_subject";
                    my $subject_meth = "virus_${subject}";
                    $self->$subject_meth( $virus_ref->{ $subject } )
                        if $virus_ref->{ $subject }
                }
            }
        }
    }
    else {
        $self->virus_handle( 'ignore' );
    }
    
    # having spam things ?
    if ( defined( my $spam_ref = $self->config->{ spam } ) && ref( $self->config->{ spam } ) ) {
        
        # what's the basic behavior ?
        DD::cop_it "behavior has to be set to 'ignore', 'scoring' or 'strict' in spam section\n"
            unless $spam_ref->{ behavior }
            && $spam_ref->{ behavior } =~ /^(?:scoring|strict|ignore)$/
        ;
        $self->spam_behavior( $spam_ref->{ behavior } );
        
        
        # how to handle recognized spam ?
        unless ( $self->spam_behavior eq 'ignore' ) {
            DD::cop_it "spam_handle has to be set to 'tag', 'bounce' or 'delete' in scoring!\n"
                unless $spam_ref->{ handle }
                && $spam_ref->{ handle } =~ /^(?:tag|bounce|delete)$/
            ;
            $self->spam_handle( $spam_ref->{ handle } );
            
            # any spam subject prefix ?
            $self->spam_subject_prefix( $spam_ref->{ spam_subject_prefix } )
                if $self->spam_handle eq 'tag' && $spam_ref->{ spam_subject_prefix };
            
            # wheter use noisy headers or not
            $self->spam_noisy_headers( $spam_ref->{ noisy_headers } || 0 );
            
            # set threshold
            if ( $self->spam_behavior eq 'scoring' ) {
                DD::cop_it "Require threshold in spam section with behavior = scoring\n"
                    unless defined $spam_ref->{ threshold };
                $self->spam_threshold( $spam_ref->{ threshold } );
            }
            
            # enable notification of recipient on bounce or delete ?
            if ( ( $self->spam_handle eq 'bounce' || $self->spam_handle eq 'delete' ) && $spam_ref->{ notify_recipient } ) {
                $self->spam_notify_recipient( 1 );
                
                # having a template for those notifications ?
                if ( $spam_ref->{ recipient_template } ) {
                    DD::cop_it "Cannot read from spam recipient_template file '$spam_ref->{ recipient_template }'\n"
                        unless -f $spam_ref->{ recipient_template };
                    $self->spam_recipient_template( $spam_ref->{ recipient_template } );
                }
            }
            else {
                $self->spam_notify_recipient( 0 );
            }
        }
    }
    else {
        $self->spam_behavior( 'ignore' );
    }
    
    # accept scoring from headers ?
    if ( $self->config->{ accept_scoring } ) {
        $self->accept_scoring( 1 );
        
        # having verify key ?
        if ( $self->config->{ doorman_verify_key } ) {
            $self->doorman_verify_key( $self->config->{ doorman_verify_key } );
        }
        
        # hmm, this is not good -> warn
        else {
            $self->logger->error( "CAUTION: You accept scoring from external Doorman servers, but don't use a verification key! Spammers can inject positive scoring!" );
        }
    }
    else {
        $self->accept_scoring( 0 );
    }
    
    # load all modules
    $self->load_modules();
}


=head2 init_dirs

Inits the queue, checks spool dir for existing files -> read them

=cut

sub init_dirs {
    my ( $self ) = @_;
    
    # check and set spool dir
    DD::cop_it "Require 'spool_dir' in config (path to directory where saving mails while filtering)\n"
        unless $self->config->{ spool_dir };
    mkpath( $self->config->{ spool_dir }, { mode => 0700 } )
        unless -d $self->config->{ spool_dir };
    DD::cop_it "Require 'spool_dir'. '". $self->config->{ spool_dir }. "' is not a directory. Please create it!\n"
        unless -d $self->config->{ spool_dir };
    $self->spool_dir( $self->config->{ spool_dir } );
    
    # make sub dirs
    my %dirs = qw(
        temp_dir                temp
        queue_dir               queue
        mime_output_dir         mime
        reinject_failure_dir    failure
        quarantine_dir          quarantine
    );
    while( my( $name, $dir ) = each %dirs ) {
        $self->config->{ $name } ||= $self->spool_dir. "/$dir";
        mkpath( $self->config->{ $name }, { mode => 0700 } )
            unless -d $self->config->{ $name };
        DD::cop_it "Could not non existing '$name' dir '". $self->config->{ $name }. "'. Please create yourself.\n"
            unless -d $self->config->{ $name };
        $self->$name( $self->config->{ $name } );
        $self->logger->debug2( "Set '$name'-dir to '". $self->$name. "'" );
    }
    
    return ;
}


=head2 start

Starts all POE servers without calling the POE::Kernel->run

=cut

sub start {
    my ( $self ) = @_;
    
    # setup lockers (shared between all)
    $self->set_locker( 'default' );
    $self->set_locker( 'database' );
    $self->set_locker( 'reporting' )
        if $self->config->{ reporting };
    
    # start forking server
    # Mail::Decency::Core::POEForking::SMTP->new( $self, {
    #     temp_mask => $self->spool_dir. "/mail-XXXXXX"
    # } );
    
}


=head2 run 

Start and run the server via POE::Kernel->run

=cut

sub run {
    my ( $self ) = @_;
    $self->start();
    
    my $server = Mail::Decency::Core::NetServer::SMTPDetective->new( {
        detective => $self,
    } );
    
    my $instances = $self->config->{ server }->{ instances } > 1 ? $self->config->{ server }->{ instances } : 2;
    $server->run(
        port              => $self->config->{ server }->{ port },
        host              => $self->config->{ server }->{ host },
        min_servers       => $instances -1,
        max_servers       => $instances +1,
        min_spare_servers => $instances -1,
        max_spare_servers => $instances,
        no_client_stdout  => 1,
        #log_level        => 4,
    );
}


=head2 train

Train spam/ham into modules

=cut

sub train {
    my ( $self, $args_ref ) = @_;
    
    # get cmd method
    my $train_cmd = $args_ref->{ spam }
        ? 'cmd_learn_spam'
        : 'cmd_learn_ham'
    ;
    
    # determine all modules being trainable (Cmd)
    my @trainable = map {
        $_->can( $train_cmd )
            ? [ $train_cmd => $_ ]
            : [ train => $_ ]
        ;
    } grep {
        $_->does( 'Mail::Decency::Detective::Core::Spam' )
        && ( $_->can( $train_cmd ) || $_->can( 'train' ) )
        && ! $_->config->{ disable_train }
    } @{ $self->childs };
    
    # none found ?
    DD::cop_it "No trainable modules enabled\n"
        unless @trainable;
    
    # strip cmd_
    $train_cmd =~ s/^cmd_//;
    
    # having move ?
    if ( $args_ref->{ move } ) {
        DD::cop_it "Move directory '$args_ref->{ move }' does not exist?\n"
            unless -d $args_ref->{ move };
        $args_ref->{ move } =~ s#\/+$##;
    }
    
    # get all files for training
    my @files = -d $args_ref->{ files }
        ? glob( "$args_ref->{ files }/*" )
        : glob( $args_ref->{ files } )
    ;
    DD::cop_it "No mails for training found for '$args_ref->{ files }'"
        unless @files;
    
    # begin training
    my ( %trained, %not_required, %errors ) = ();
    print "Will train ". ( scalar @files ). " messages as ". ( $args_ref->{ spam } ? 'SPAM' : 'HAM' ). "\n";
    
    my $start_ref = [ gettimeofday() ];
    
    my $counter = 0;
    my $amount  = scalar @files;
    foreach my $file( @files ) {
        print "". ( ++$counter ). " / $amount: '$file'\n";
        
        my ( $th, $tn ) = tempfile( $self->temp_dir. "/train-XXXXXX", UNLINK => 0 );
        close $th;
        copy( $file, $tn );
        my $size = -s $tn;
        $self->session_init( $tn, $size );
        
        foreach my $ref( @trainable ) {
            my ( $method, $module ) = @$ref;
            
            # check wheter mail is spam or not
            $self->session->spam_score( 0 );
            eval {
                $module->handle;
            };
            
            # stop here, if ..
            if (
                
                # .. mail should be spam and is recognized as such
                ( $args_ref->{ spam } && $self->session->spam_score < 0 )
                
                # .. mail should NOT be spam and also not recognized as spam
                || ( $args_ref->{ ham } && $self->session->spam_score >= 0 ) 
            ) {
                print "  = $module / Already trained\n";
                $not_required{ "$module" }++;
                next;
            }
            
            # run filter with train command now
            my ( $res, $result, $exit_code );
            
            if ( $method =~ /^cmd_/ ) {
                eval {
                    ( $res, $result, $exit_code ) = $module->cmd_filter( $train_cmd );
                };
            }
            else {
                eval {
                    ( $res, $result, $exit_code ) = $module->train( $args_ref->{ spam } ? 'spam' : 'ham' );
                };
            }
            my $error = $@;
            
            # having unexpected error
            if ( $error || ( $exit_code && $result ) ) {
                my $message = $error || $result;
                print "  * $module / Error\n*****\n$message\n*****\n\n";
                $errors{ "$module" }++;
            }
            
            # all ok -> trained
            else {
                print "  + $module / Success\n";
                $trained{ "$module" }++;
            }
        }
        unlink( $tn );
        unlink( "$tn.info" ) if -f "$tn.info";
        
        my $diff = tv_interval( $start_ref, [ gettimeofday() ] );
        printf "  > %.2f seconds remaining\n", ( ( $diff / $counter ) * $amount ) - $diff;
        
        if ( $args_ref->{ move } ) {
            ( my $target = $file ) =~ s#^.*\/##;
            $file = abs_path( $file );
            $target = abs_path( "$args_ref->{ move }/$target" );
            $target =~ s/[^0-9a-zA-Z\-_\.\/]/-/g;
            $target =~ s/\-\-+/-/g;
            $target =~ s/\-+$//;
            $target =~ s/^\-+//;
            move( $file, $target )
                or DD::cop_it "Move error: $!\n";
            DD::cop_it "Oops, cannot move '$file' -> '$target'\n" unless -f $target;
        }
        elsif ( $args_ref->{ remove } ) {
            unlink( $file );
        }
    }
    
    # print out skipped (ham/spam)
    if ( scalar keys %not_required ) { 
        print "\n**** Not Required ****\n";
        foreach my $name( sort keys %not_required ) {
            print "$name: $not_required{ $name }\n";
        }
    }
    
    # print out trained (ham/spam)
    if ( scalar keys %trained ) { 
        print "\n**** Trained ****\n";
        foreach my $name( sort keys %trained ) {
            print "$name: $trained{ $name }\n";
        }
    }
    else {
        print "\n**** None trained ****\n";
    }
    
    # print out errors (ham/spam)
    if ( scalar keys %errors ) {
        print "\n**** Errors ****\n";
        foreach my $name( sort keys %errors ) {
            print "$name: $errors{ $name }\n";
        }
    }
    else {
        print "\n**** No Errors ****\n";
    }
}



=head2 get_handlers

Returns code ref to handlers

    my $handlers_ref = $detective->get_handlers();
    $handlers_ref->( {
        file => '/tmp/somefile',
        size => -s '/tmp/somefile',
        from => 'sender@domain.tld',
        to   => 'recipient@domain.tld',
    } );

=cut

sub get_handlers {
    my ( $self ) = @_;
    
    weaken( my $self_weak = $self );
    
    # { file => '/path/to/file', from => "from@domain.tld", to => "to@domain.tld" }
    return sub {
        return $self_weak->handle_safe( @_ );
    }
    
}

=head2 handle_safe

=cut

sub handle_safe {
    my ( $self, $ref ) = @_;
    
    $self->logger->debug3( "Handle new: $ref->{ file }, from: $ref->{ from }, to: $ref->{ to }" );
    
    my ( $ok, $message, $status );
    
    # better eval that.. the server shold NOT die .
    eval {
        
        # write the from, to, size and such to yaml file
        open my $fh, ">", $ref->{ file }. ".info"
            or DD::cop_it "Cannot open '$ref->{ file }' for read\n";
        
        print $fh YAML::Dump( $ref );
        close $fh;
        
        ( $ok, $message, $status )
            = $self->handle( $ref->{ file }, -s $ref->{ file }, $ref->{ args } || undef );
    };
    
    # log out error
    if ( $@ ) {
        $self->logger->error( "Error handling '$ref->{ file }': $@" );
    }
    
    return ( $ok, $message, $status );
}


=head2 handle

Calls the handle method of all registered filters.

Will be called from the job queue

=cut

sub handle {
    my ( $self, $file, $size, $args_ref ) = @_;
    
    # start
    my $start_time_ref = [ gettimeofday() ];
    
    # setup mail info (mime, from, to and such)
    eval {
        $self->session_init( $file, $size, $args_ref );
    };
    if ( $@ ) {
        $self->logger->error( "Cannot init session: $@" );
        return;
    }
    
    # handle by all filters
    my $status = 'ongoing';
    
    EACH_FILTER:
    foreach my $filter( @{ $self->childs } ) {
        
        # get handle (bool) and error (string?)
        ( my $handle, $status, my $err )
            = $self->handle_child( $filter, [] );
        
        # no handle
        next unless $handle;
        
        # final result ..
        last EACH_FILTER if $status ne 'ongoing';
    }
    
    # write mail info to caches
    $self->session_write_cache;
    
    # finish all
    #   * status: ongoing, spam, virus
    #   * final code: DETECTIVE_FINAL_*
    ( $status, my $final_code ) = $self->finish( $status );
    
    # time diff
    my $run_diff = tv_interval( $start_time_ref, [ gettimeofday() ] );
    
    # run post hooks
    ( $status, $final_code ) = $self->run_hooks( 'post_finish', [ $status, $final_code ] );
    # ( $status, $final_code ) = $self->run_hooks( 'post_finish', [ {
    #     status     => $status,
    #     final_code => $final_code,
    #     diff       => $run_diff,
    #     details    => join( ' ## ', @{ $self->session->spam_details } )
    # } ] );
    
    # update server stats ?
    eval {
        $self->update_server_stats( $status )
            if $self->enable_server_stats;
    };
    $self->logger->error( "Error in server stats: $@" ) if $@;
    
    # get spam details
    my $spam_details = join( ' / ', @{ $self->session->spam_details } );
    
    # write reporting ?
    eval {
        $self->write_report( $status, join( ' ## ', @{ $self->session->spam_details } ) )
            if $self->reporting_enabled;
    };
    $self->logger->error( "Error in reporting: $@" ) if $@;
    
    # clear all
    $self->session->cleanup
        unless $args_ref->{ no_session_cleanup };
    
    # return the final code to the SMTP server, which will then either force the mta
    #   (postfix) to bounce the mail by rejecting it or accept, to 
    if ( $final_code == DETECTIVE_FINAL_OK || $final_code == DETECTIVE_FINAL_DELETED ) {
        return ( 1, undef, $status );
    }
    else {
        return ( 0, $spam_details, $status );
    }
}

=head2 handle_error

Called on error from handle_child method

Returns on of the following stati:

=over

=item * ok

A non fatal error (eg timeout of a single module)

=item * spam

Mail recognized as spam

=item * virus

Mail recognized as virus

=item * drop

Mail to be dropped silently

=back

=cut

sub handle_error {
    my ( $self, $err, $filter ) = @_;
    
    given ( $err ) {
        
        # got final SPAM
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Spam' ) ) {
            $self->session->add_spam_details( $_->message );
            $self->logger->debug0( "Mail is spam after $filter, message: ". $_->message );
            return 'spam';
        }
        
        # got final VIRUS
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Virus' ) ) {
            $self->session->add_spam_details( $_->message );
            $self->logger->debug0( "Mail is virus after $filter, message: ". $_->message );
            return 'virus';
        }
        
        # error: timeout
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Drop' ) ) {
            $self->logger->debug0( "Dropping mail after $filter" );
            return 'drop';
        }
        
        # file to big, ignore, log
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::FileToBig' ) ) {
            $self->logger->debug0( "File to big for $filter" );
            return 'ongoing';
        }
        
        # error: timeout
        when( blessed( $_ ) && $_->isa( 'Mail::Decency::Core::Exception::Timeout' ) ) {
            $self->logger->error( "Timeout in $filter" );
            return 'ongoing';
        }
        
        # got some unknown error
        default {
            $self->logger->error( "Error in $filter: $_" );
            return 'ongoing';
        }
    }
    return 'ongoing';
}


=head2 finish

Finish MAIL

=cut

sub finish {
    my ( $self, $status ) = @_;
    
    # default final code ..
    my $final_code = DETECTIVE_FINAL_OK;
    
    # run pre hooks
    ( $status, $final_code ) = $self->run_hooks( 'pre_finish', [ $status, $final_code ] );
    
    # found virus ? take care of it!
    if ( $status eq 'virus' ) {
        $final_code = $self->finish_virus;
    }
    
    # recognized spam ? see to it.
    elsif ( $status eq 'spam' ) {
        $final_code = $self->finish_spam;
    }
    
    # ok, all ok -> regular finish
    elsif ( $status ne 'drop' ) {
        $final_code = $self->finish_ok;
    }
    
    return ( $status, $final_code );
}


=head2 finish_spam

Called after modules have filtered the mail. Will perform according to spam_handle directive.

=over

=item * delete

Remvoe mail silently

=item * bounce

Bounce mail back to sender

=item * ignore

Ignore mail, simply forward

=item * tag

Tag mail, insert X-Decency-Status and X-Decency-Score headers. If detailed: also X-Decency-Details header. 

=back

=cut

sub finish_spam {
    my ( $self ) = @_;
    
    my $session = $self->session;
    my $score   = $session->spam_score;
    my @info    = @{ $session->spam_details };
    
    # just remove and ignore
    if ( $self->spam_handle eq 'delete' ) {
        $self->logger->info( sprintf( 'Delete spam mail from %s to %s, size %d with score %d',
            $session->from, $session->to, $session->file_size, $score ) );
        return DETECTIVE_FINAL_DELETED;
    }
    
    # do bounce mail
    elsif ( $self->spam_handle eq 'bounce' ) {
        $self->logger->info( sprintf( 'Bounce spam mail from %s to %s, size %d with score %d',
            $session->from, $session->to, $session->file_size, $score ) );
        
        return DETECTIVE_FINAL_BOUNCE;
    }
    
    # do ignore mail, don't tag, do nothing like this
    elsif ( $self->spam_handle eq 'ignore' ) {
        return $self->reinject;
    }
    
    # do tag mail
    else {
        my $header = $session->mime->head;
        
        # prefix subject ?
        if ( $self->has_spam_subject_prefix ) {
            my $subject = $header->get( 'Subject' ) || '';
            ( my $prefix = $self->spam_subject_prefix ) =~ s/ $//;
            $header->replace( 'Subject' => "$prefix $subject" );
        }
        
        # add tag
        $session->mime_header( replace => 'X-Decency-Result'  => 'SPAM' );
        $session->mime_header( replace => 'X-Decency-Score'   => $score );
        $session->mime_header( replace => 'X-Decency-Details' => join( " | ", @info ) )
            if $self->spam_noisy_headers;
        
        # update mime
        $self->session->write_mime;
        
        # reinject
        return $self->reinject;
    }
}


=head2 finish_virus

Mail has been recognized as infected. Handle it according to virus_handle

=over

=item * bounce

Send back to sender

=item * delete

Silently remove

=item * quarantine

Do not deliver mail, move it into quarantine directory.

=item * ignore

Deliver to recipient

=back

=cut

sub finish_virus {
    my ( $self ) = @_;
    
    # get session..
    my $session = $self->session;
    
    # don't do that .. however, here is the bounce
    if ( $self->virus_handle eq 'bounce' ) {
        $self->logger->info( sprintf( 'Bounce virus infected mail from %s to %s, size %d with virus "%s"',
            $session->from, $session->to, $session->file_size, $session->virus ) );
        return DETECTIVE_FINAL_BOUNCE;
    }
    
    # don't do that .. however, here is the bounce
    elsif ( $self->virus_handle eq 'delete' ) {
        $self->logger->info( sprintf( 'Delete virus infected mail from %s to %s, size %d with virus "%s"',
            $session->from, $session->to, $session->file_size, $session->virus ) );
        return DETECTIVE_FINAL_DELETED;
    }
    
    # inject mail into qurantine dir
    elsif ( $self->virus_handle eq 'quarantine' ) {
        $self->logger->info( sprintf( 'Quarantine virus infected mail from %s to %s, size %d with virus "%s"',
            $session->from, $session->to, $session->file_size, $session->virus ) );
        $self->_save_mail_to_dir( 'quarantine_dir' );
        return DETECTIVE_FINAL_DELETED;
    }
    
    # don't do that .. 
    else {
        $self->logger->info( sprintf( 'Delivering virus infected mail from %s to %s, size %d with virus "%s"',
            $session->from, $session->to, $session->file_size, $session->virus ) );
        return $self->reinject;
    }
}


=head2 finish_ok

Called after mails has not been recognized as virus nor SPAM. Do deliver to recipient. With noisy_headers, include spam X-Decency-(Result|Score|Details) into header.

=cut

sub finish_ok {
    my ( $self ) = @_;
    
    # being noisy -> set spam info even if not spam
    if ( $self->spam_noisy_headers ) {
        my $session = $self->session;
        $session->mime_header( replace => 'X-Decency-Result'  => 'GOOD' );
        $session->mime_header( replace => 'X-Decency-Score'   => $self->session->spam_score );
        $session->mime_header( replace => 'X-Decency-Details' => join( " | ",
            @{ $session->spam_details } ) );
        
        # update mime
        $self->session->write_mime;
    }
    
    return $self->reinject;
}


=head2 reinject

Reinject mails to postfix queue, or archive in send-queue

=cut

sub reinject {
    my ( $self, $type ) = @_;
    
    # disabled for this one mail
    if ( $self->session->disable_reinject ) {
        $self->logger->debug2( "Reinjection is disabled by session" );
        return DETECTIVE_FINAL_OK;
    }
    
    # do no reinject if no reinjection is defined
    unless ( $self->can_reinject ) {
        $self->logger->debug2( "Do not reinject mail, cause no reinject is set" );
        return DETECTIVE_FINAL_OK;
    }
    
    # get all reinjections
    my $reinjects_ref = $self->reinjections;
    my $any_delivered = 0;
    
    # ok, the "message" method does not contain the last
    #   response, but the last SUCCESSFUL response.. not good
    #   if we want to determine the actual error response
    no strict 'refs';
    my $oldgetline = *{'Net::Cmd::getline'}{ CODE };
    my $last_msg = \( '' );
    local *{'Net::Cmd::getline'} = sub {
        my $line = $oldgetline->( @_ );
        ( undef, my $msg ) = split( ' ', $line, 2 );
        chomp( $msg );
        $last_msg = \$msg;
        return $line;
    };
    use strict 'refs';
    
    # perform all reinjections
    foreach my $reinject_ref( @$reinjects_ref ) {
        
        # if we have already delivered the mail in this
        #   reinject instance is not a copy -> do not use
        next if $any_delivered && ! $reinject_ref->{ copy };
        
        # get host
        my $reinject_host = ( $reinject_ref->{ host } || "localhost" ). ":". ( $reinject_ref->{ port } || 10250 );
        
        my $dbg_str = sprintf( 'reinject-host: "%s", from: "%s", to: "%s"',
            $reinject_host, $self->session->from, $self->session->orig_to );
        
        eval {
            
            # determine smtp class
            my $class = $reinject_ref->{ ssl }
                ? 'Net::SMTP::SSL'
                : ( $reinject_ref->{ tls }
                    ? 'Net::SMTP::TLS'
                    : 'Net::SMTP'
                )
            ;
            
            # for tls we require pre auth
            my %pre_auth = $class =~ /::TLS$/ && $reinject_ref->{ user }
                ? ( User => $reinject_ref->{ user }, Password => $reinject_ref->{ pass } )
                : ()
            ;
            
            # init connection
            my $smtp = $class->new(
                $reinject_host,
                Hello   => $reinject_ref->{ hello } || 'decency',
                Timeout => 30,
                Debug   => $reinject_ref->{ debug } || $ENV{ DECENCY_REINJECT_DEBUG } || 0,
                %pre_auth
            ) or DD::cop_it "Could not open SMTP connection: ". ( join( ", ", grep { defined && $_ } ( $!, $@ ) ) || "" );
            DD::cop_it "Could not open SMTP connection: ". ( join( ", ", grep { defined && $_ } ( $!, $@ ) ) || "" )
                unless $smtp;
            
            # auth ?
            $smtp->auth( $reinject_ref->{ user }, $reinject_ref->{ pass } || '' )
                or DD::cop_it [ auth => $smtp->code, $$last_msg ]
                if $reinject_ref->{ user } && ! $class =~ /::TLS$/;
            
            # send hello
            #$smtp->hello( $reinject_ref->{ hello } || 'decency' );
            $smtp->mail( $self->session->from )
                or DD::cop_it [ from => $smtp->code, $$last_msg ];
            $smtp->to( $self->session->orig_to )
                or DD::cop_it [ to => $smtp->code, $$last_msg ];
            $smtp->data
                or DD::cop_it [ data => $smtp->code, $$last_msg ];
            
            # parse file and print all lines
            open my $fh, '<', $self->session->current_file;
            while ( my $l = <$fh> ) {
                chomp $l;
                $smtp->datasend( $l. CRLF )
                    or DD::cop_it $!;
            }
            
            # end data
            $smtp->dataend
                or DD::cop_it [ dataend => $smtp->code, $$last_msg ];
            
            # get reponse message containg new ID
            my $message = $$last_msg;
            
            # quit connection
            $smtp->quit
                or DD::cop_it [ quit => $smtp->code, $$last_msg ];
            
            # is delivered
            $any_delivered ++;
            
            # determine message
            if ( $message && $message =~ /queued as ([A-Z0-9]+)/ ) {
                my $next_id = $1;
                $self->logger->debug0( "Reinjected mail as $next_id ($dbg_str)" );
                $self->session->next_id( $next_id );
                $self->session_write_cache;
            }
            else {
                $self->logger->debug0(
                    "Failed to determine ID after successful reinject, response: '".
                    $message. "' ($dbg_str)" );
            }
        };
        
        # got error
        if ( my $err= $@ ) {
            
            # this is an not accepted SMTP command
            if ( ref( $err ) ) {
                my ( $type, $code, $msg ) = @$err;
                chomp $msg;
                $self->logger->error( sprintf(
                    'Error in reinject with SMTP-%s: (%s / code: "%s", msg: "%s")',
                    uc( $type ), $dbg_str, $code, $msg ) );
            }
            
            # somethin else..
            else {
                $self->logger->error( "Error in reinject: $err" );
            }
        }
    }
    
    # delivered OK
    return DETECTIVE_FINAL_OK if $any_delivered;
    
    # save failed mail to failure dir
    my $file = $self->_save_mail_to_dir( 'reinject_failure_dir' );
    $self->logger->error( "Could NOT reinject mail in any host, saved mail to '$file'" );
    
    # do not bounce.. 
    return DETECTIVE_FINAL_OK
        unless $self->bounce_on_reinject_failure;
    
    # do probably bounce
    return DETECTIVE_FINAL_ERROR;
}



=head2 send_notify

Send either spam or virus notification

    $detective->send_notify( virus => recipient => 'recipient@domain.tld' );

=cut

sub send_notify {
    my ( $self, $type, $direction, $to ) = @_;
    my $mime = $self->session->mime;
    
    eval {
        
        # build the multipart surrounding
        my $subject_method = "${type}_${direction}_subject";
        my $encaps = MIME::Entity->build(
            Subject    => $self->$subject_method || uc( $type ). " notification",
            From       => $self->notification_from,
            To         => $to,
            Type       => 'multipart/mixed',
            'X-Mailer' => 'Decency'
        );
        
        my @data = ();
        my $template_meth = "${type}_${direction}_template"; # eg spam_recipient_template
        
        # get session
        my $session = $self->session;
        
        # having a custom template ..
        if ( defined $self->$template_meth ) {
            
            # read template ..
            open my $fh, '<', $self->$template_meth
                or DD::cop_it "Cannot open '". $self->$template_meth. "' for read: $!\n";
            
            # add reason of rejection
            my %template_vars = ( reason => $type );
            
            # add virus name
            $template_vars{ virus } = $session->virus if $type eq 'virus';
            
            # add from, to
            $template_vars{ $_ } = $session->$_ for qw/ from to /;
            
            # add subject, if any
            $template_vars{ subject } = $mime->head->get( 'Subject' ) || "(no subject)";
            
            # read and parse template
            @data = map {
                chomp;
                s/<%\s*([^%]+)\s*%>/defined $template_vars{ $1 } ? $template_vars{ $1 } : $1/egms;
                $_;
            } <$fh>;
            
            # close template
            close $fh;
        }
        else {
            push @data, "Your mail to ". $session->to. " has been rejected.";
            push @data, "";
            push @data, "Subject of the mail: ". ( $mime->head->get( 'Subject' ) || "(no subject)" );
            push @data, "";
            push @data, "Reason: categorized as ". $type. ( $type eq 'virus' ? " (". $session->virus. ")" : "" );
        }
        
        # add the template 
        $encaps->add_part( MIME::Entity->build(
            Type     => 'text/plain',
            Encoding => 'quoted-printable',
            Data     => \@data
        ) );
        
        unless ( $self->reinject( $encaps ) == DETECTIVE_FINAL_OK ) {
            DD::cop_it "Error sending $type $direction notification mail to $to\n";
        }
    };
    
    # having error ?
    if ( $@ ) {
        $self->logger->error( "Error in mime encapsulation: $@" );
        return 0;
    }
    
    return 1;
}






=head2 session_init

Inits the L<Mail::Decency::Core::SessionItem::Detective> session object for the current handled mail.

=cut

sub session_init {
    my ( $self, $file, $size, $args_ref ) = @_;
    
    # init args
    $args_ref ||= {};
    
    # setup new info
    ( my $init_id = $file ) =~ s/[\/\\]/-/g;
    my %verify = $self->has_doorman_verify_key
        ? ( verify_key => $self->doorman_verify_key_rsa )
        : ()
    ;
    $self->session( Mail::Decency::Core::SessionItem::Detective->new(
        id                  => $init_id || "unknown-". time(),
        file                => $file,
        mime_output_dir     => $self->mime_output_dir,
        cache               => $self->cache,
        recipient_delimiter => $self->recipient_delimiter,
        %verify
    ) );
    my $session = $self->session;
    
    # reinject
    $self->run_hooks( 'session_init' );
    
    #
    # RETREIVE QUEUE ID, UPDATE FROM DETECTIVE CACHE
    #
    
    # having id from args
    if ( exists $args_ref->{ queue_id } ) {
        $session->id( $args_ref->{ queue_id } )
            if $args_ref->{ queue_id };
    }
    
    elsif ( $args_ref->{ doorman_session_data } ) {
        $session->update_from_doorman_cache( $args_ref->{ doorman_session_data } );
    }
    
    # try get from somewhere else
    else {
        
        # get last queue ID
        my @received = $session->mime->head->get( 'Received' );
        my $received = shift @received;
        if ( $received && $received =~ /E?SMTP id ([A-Z0-9]+)/ms ) {
            my $id = $1;
            $session->id( $id );
            
            # try read info from Doorman from cache
            my $cached = $self->cache->get( "QUEUE-$id" ) || $self->cache->get( "DOORMAN-$id" );
            $session->update_from_cache( $cached )
                if $cached && ref( $cached );
            #$self->loggger->info( "
        }
        
        # oops, this should not happen, maybe in debug cases, if mails
        #   are directyly injected into the Detective ?!
        elsif ( ! $self->encapsulated ) {
            $self->logger->error( "Could not determine Queue ID! No 'Received' header found! Postfix should set this!" );
        }
    }
    
    # retreive scoring from Doorman, if any
    $session->retreive_doorman_scoring( $self->accept_scoring );
    
    
    return $session;
}


=head2 session_write_cache

Write session to cache. Called at the end of the session.

=cut

sub session_write_cache {
    my ( $self ) = @_;
    
    # get session to be cached
    my $session_ref = $self->session->for_cache;
    
    # save to cache (max 10min..)
    $self->cache->set( "QUEUE-$session_ref->{ queue_id }", $session_ref, time() + 600 );
    
    # write next to cache
    if ( $session_ref->{ next_id } ) {
        my %next = %{ $session_ref };
        $next{ queue_id } = $session_ref->{ next_id };
        $next{ prev_id }  = $session_ref->{ queue_id };
        $next{ next_id }  = undef;
        $self->cache->set( "QUEUE-$next{ queue_id }", \%next, time() + 600 );
        
        $self->logger->debug3( "Store next id $session_ref->{ next_id } for $session_ref->{ queue_id }" );
    }
    
    # re-write prev to cache (keep alive)
    if ( $session_ref->{ prev_id } ) {
        
        # get cached prev
        my $prev_cached = $self->cache->get( "QUEUE-$session_ref->{ prev_id }" );
        
        # create new prev
        my %prev = %{ $session_ref };
        $prev{ queue_id } = $session_ref->{ prev_id };
        $prev{ prev_id }  = $prev_cached ? $prev_cached->{ prev_id } : undef;
        $prev{ next_id }  = $session_ref->{ queue_id };
        $self->cache->set( "QUEUE-$prev{ queue_id }", \%prev, time() + 600 );
        $self->logger->debug3( "Store prev id $session_ref->{ prev_id } for $session_ref->{ id }" );
    }
    
    return ;
}




#
#       SPAM
#





=head2 add_spam_score

Add spam score (positive/negative). If threshold is reached -> throw L<Mail::Decency::Core::Exception::Spam> exception.

=cut

sub add_spam_score {
    my ( $self, $weight, $module, @msg ) = @_;
    
    # get info
    my $session = $self->session;
    
    # add score
    $session->add_spam_score( $weight );
    
    # add info
    my $message_ref = $#msg == 0 ? $msg[0] : do { pop @msg };
    $message_ref ||= [];
    $message_ref = [ $message_ref ] unless ref( $message_ref );
    $session->add_spam_details( join( "; ",
        "Module: $module",
        "Score: $weight",
        @$message_ref
    ) );
    
    # provide result based on config settings
    if ( (
            # strict hit
            $session->spam_score < 0
            && $self->spam_behavior eq 'strict'
        )
        || (
            # threshold hit
            $self->spam_behavior eq 'scoring'
            && $self->spam_threshold_reached( $session->spam_score )
    ) ) {
        # throw ..
        Mail::Decency::Core::Exception::Spam->throw( { message => "Spam found" } );
    }
}


=head2 virus_info

Virus is found. Throw L<Mail::Decency::Core::Exception::Virus> exception.

=cut

sub found_virus {
    my ( $self, $info ) = @_;
    $self->session->virus( $info );
    
    # throw final exception
    Mail::Decency::Core::Exception::Virus->throw( { message => "Virus found: $info" } );
}


=head2 _save_mail_to_dir

Save a mail to some dir. Called from quarantine or reinjection failures

=cut

sub _save_mail_to_dir {
    my ( $self, $dir_name ) = @_;
    
    my $session = $self->session;
    
    # determine from with replaced @
    ( my $from = $session->from || "unkown" ) =~ s/\@/-at-/;
    
    # determine to with replaced @
    ( my $to = $session->to || "unkown" ) =~ s/\@/-at-/;
    
    # format file <time>-<from>-<to> and replace possible problematic chars
    ( my $from_to = time(). "_FROM_${from}_TO_${to}" ) =~ s/[^\p{L}\d\-_\.]//gms;
    
    # get tempfile (assures uniqueness)
    my ( $th, $failure_file )
        = tempfile( $self->$dir_name. "/$from_to-XXXXXX", UNLINK => 0 );
    close $th;
    
    # copy file to archive folder
    copy( $session->current_file, $failure_file );
    
    return $failure_file;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

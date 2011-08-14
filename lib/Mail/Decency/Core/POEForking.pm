package Mail::Decency::Core::POEForking;

use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Scalar::Util qw/ weaken /;
use Time::HiRes qw/ usleep /;
use Proc::ProcessTable;
use POE::Wheel::ReadWrite;
#use POE::API::Peek;
use Data::Dumper;

use base qw/
    Exporter
/;

use POE qw/
    Filter::Postfix::Base64
    Filter::Postfix::Null
    Filter::Postfix::Plain
    Wheel::ReadWrite
    Wheel::SocketFactory
/;

$|= 1;

our @EXPORT = qw/
    cleanup_client
    cleanup_stop
    client_start
    handle_conn_error
/;

our %SESSIONS = ();

=head1 NAME

Mail::Decency::Core::POEForking

=head1 DESCRIPTION

Base class for Postfix and SMTP server. Implements forking


=head1 METHODS


=head2 new

=cut

sub new {
    my ( $class, $decency, $args_ref ) = @_;
    
    weaken( my $decency_weak = $decency );
    POE::Session->create(
        inline_states => {
            _start             => sub {
                if ( $args_ref->{ callback_start } ) {
                    $args_ref->{ callback_start }->( $decency_weak, @_ );
                }
                &forking_startup( @_ );
            },
            _stop              => \&forking_halt,
            fork_child         => \&forking_fork_child,
            catch_sig_int      => \&forking_catch_sig_int,
            catch_sig_term     => \&forking_catch_sig_term,
            catch_sig_child    => \&forking_catch_sig_child,
            catch_sig_usr2     => \&forking_catch_reload,
            new_connection     => \&forking_new_connection,
            client_error       => \&forking_client_error,
            # new_client_session => sub {
            #     my ( $heap, $kernel, $client_session ) = @_[ HEAP, KERNEL, SENDER ];
            #     warn ">> $heap->{ is_child } / ADD $$ = ". $client_session->ID. " / @_\n";
            #     warn "> L ". join( ", ", $kernel->alias_list ). "\n";
            #     $heap->{ client_sessions }->{ $client_session->ID } = $client_session;
            # },
            # _parent             => sub {
            #     my ( $heap, $event, $args ) = @_[ HEAP, ARG0, ARG1 ];
            #     warn ">> PARENT $$ $event, $args\n";
            #     $heap->{ decency }->logger->error( "** PARENT $event, $args" );
            # },
            # _child             => sub {
            #     my ( $heap, $event, $args ) = @_[ HEAP, ARG0, ARG1 ];
            #     warn ">> CHILD $$ $event, $args\n";
            #     $heap->{ decency }->logger->error( "** CHILD $event, $args" );
            # },
            # _default => sub {
            #     my ( $heap, $session, $event, $args ) = @_[ HEAP, SESSION, ARG0, ARG1 ];
            #     #warn ">> DEFA $$ $event, $args\n";
            #     $heap->{ decency }->logger->error( "** UNKNOWN EVENT $event, $args IN ". $session->ID . " / $$" );
            # }
        },
        heap => {
            decency => $decency_weak,
            conf    => $decency_weak->config,
            args    => $args_ref,
            class   => $class
        }
    );
}


=head2 forking_startup

Server startup event

=cut

sub forking_startup {
    my ( $kernel, $heap, $session ) = @_[ KERNEL, HEAP, SESSION ];
    
    # listen to port and adress
    $heap->{ server } = POE::Wheel::SocketFactory->new(
        BindAddress  => $heap->{ conf }->{ server }->{ host },
        BindPort     => $heap->{ conf }->{ server }->{ port },
        SuccessEvent => "new_connection",
        FailureEvent => "client_error",
        Reuse        => "yes"
    );
    
    $heap->{ parent_pid } = $$;
    
    $kernel->sig( 13 => sub { warn "> SOME EVENT [$$]\n" } );
    #$kernel->alias_set( 'parent' );
    
    # master does not list
    $heap->{ server }->pause_accept();
    
    # bing sig int to final sig int (bye bye)
    $kernel->sig( INT  => "catch_sig_int" );
    $kernel->sig( TERM => "catch_sig_term" );
    $kernel->sig( USR2 => "catch_sig_usr2" );
    
    # this is the parental process, set list of childs
    $heap->{ childs } = {};
    
    # mark as parent
    $heap->{ is_child } = 0;
    
    # startup message
    $heap->{ server_address } = "$heap->{ conf }->{ server }->{ host }:$heap->{ conf }->{ server }->{ port }";
    $heap->{ decency }->logger->debug3( "Start server on $heap->{ server_address } ($$)" );
    
    # begin create childs
    $kernel->yield( 'fork_child' );
}


=head2 forking_halt

All goes down

=cut

sub forking_halt {
    my ( $heap, $session ) = @_[ HEAP, SESSION ];
    delete $SESSIONS{ $session->ID };
    $heap->{ decency } && $heap->{ decency }->logger->debug3( "Stop ". ( $heap->{ is_child } ? "child" : "parent" ). " server on $heap->{ server_address } ($$)" );
}


=head2 forking_fork_child

Create a new child

=cut

sub forking_fork_child {
    my ( $kernel, $heap, $session ) = @_[ KERNEL, HEAP, SESSION ];
    
    # childs don't fork new childs!
    return if $heap->{ is_child } || $heap->{ is_going_down };
    
    # daemon mode -> call forked from parent, just once
    if ( $ENV{ DECENCY_PARENT_IS_FORKED } ) {
        $kernel->has_forked;
        $ENV{ DECENCY_PARENT_IS_FORKED } = 0;
    }
    
    # main fork loop
    my $max = $heap->{ conf }->{ server }->{ instances } || 3;
    DD::cop_it "Require at least 1 child, got '$max'"
        if $max < 1;
    
    # start the childs
    while( scalar( keys %{ $heap->{ childs } } ) < $max ) {
        my $pid = fork();
        
        # oops, could not fork!
        unless ( defined $pid ) {
            $heap->{ decency }->logger->error( "Failed forking child: $!" );
            
            # try, try again!
            $kernel->delay( fork_child => 5 );
            return;
        }
        
        # we are in parent process:
        elsif ( $pid ) {
            
            # add new child
            $heap->{ decency }->logger->debug3( "Add new child $pid to list" );
            $heap->{ childs }->{ $pid } ++;
            $heap->{ decency }->add_child_pid( $pid => scalar time() );
            
            # bind sig child to handler (if child dies -> this will be called)
            $kernel->sig_child( $pid, "catch_sig_child" );
        }
        
        # we are the child
        else {
            
            # tell everybody we are here, new and forked
            $kernel->has_forked;
            
            # accept incomming
            $heap->{ is_child }++;
            $heap->{ server }->resume_accept();
            
            # setup database, caches and all
            $heap->{ decency }->this_is_a_child();
            $heap->{ decency }->setup()
                if $heap->{ decency }->can( 'setup' );
            
            # assure no misidentification
            $heap->{ childs } = {};
            
            return;
        }
    }
    
}


=head2 forking_catch_sig_int

Catch the death of the master process

=cut

sub forking_catch_sig_int {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    
    $heap->{ decency }->logger->debug3( "Caught SIG Int ($$) in ". ( $heap->{ is_child } ? "child instance" : "parent server" ) );
    
    # remove one self
    delete $heap->{ server };
    
    # close all client session
    unless ( $heap->{ is_child } ) {
        kill TERM => $_ for keys %{ $heap->{ childs } };
        $kernel->post( $_, 'good_night' )
            for values %{ $heap->{ client_sessions } };
        delete $heap->{ client_sessions };
        
        # close all childs (only for parent, if not already called
        unless ( $heap->{ is_going_down } ) {
            
            # mark shutdown
            $heap->{ is_going_down } = 1;
            
            my $sub_running = sub {
                my $pid = shift;
                my $t = Proc::ProcessTable->new;
                return scalar ( grep { $_->pid == $pid && $_->state ne 'defunct' } @{ $t->table } ) > 0;
            };
            
            # all child pids ..
            foreach my $child_pid( keys %{ $heap->{ childs } } ) {
                eval {
                    
                    # wait for 3 seconds for child to go down..
                    local $SIG{ ALRM } = sub {
                        DD::cop_it "Timeout in killing\n";
                    };
                    alarm( 5 );
                    my $running = $sub_running->( $child_pid );
                    DD::dbg "Found running $child_pid: $running\n";
                    kill "INT", $child_pid;
                    
                    # do the wait ..
                    DD::dbg "Shutting down $child_pid: ";
                    #while ( my $ok = kill 0, $child_pid ) {
                    while( my $up = $sub_running->( $child_pid ) ) {
                        DD::dbg " * Up $child_pid"; 
                        usleep( 100_000 );
                    }
                    DD::dbg " OK, $child_pid is shut down"; 
                    
                    # hsa been killed ..
                    alarm( 0 );
                };
                
                # not killed ? try harder!
                if ( $@ ) {
                    #warn ">> E $@\n";
                    my $running = kill 0, $child_pid;
                    DD::dbg " FAILED ($running, $child_pid) -> kill hard\n";
                    kill KILL => $child_pid;
                }
            }
            
        }
    }
    
    else {
        delete $heap->{ decency };
    }
    
    # say good night
    $kernel->sig_handled();
}


=head2 forking_catch_sig_term

Catch the death of the master process

=cut

sub forking_catch_sig_term {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    
    $heap->{ decency }->logger->debug3( "Caught SIG Term ($$) in ". ( $heap->{ is_child } ? "child instance" : "parent server" ) );
    
    forking_catch_sig_int( @_ );
}



=head2 forking_catch_sig_child

Catch the death of a child .. sad as it might be

=cut

sub forking_catch_sig_child {
    my ( $kernel, $heap, $child_pid ) = @_[ KERNEL, HEAP, ARG1 ];
    
    # assure child pid is removed
    $heap->{ decency }->remove_child_pid( $child_pid )
        unless $heap->{ decency }->is_child;
    
    # if there is NO such child -> return
    return unless delete $heap->{ childs }->{ $child_pid };
    
    # close all client session
    if ( defined $heap->{ client_sessions } ) {
        $kernel->post( $_, 'good_night' ) for values %{ $heap->{ client_sessions } };
        delete $heap->{ client_sessions };
    }
    
    # create new child -> if the server is still there!! (not been killed..)
    if ( exists $heap->{ server } && ! $heap->{ is_child } && ! $heap->{ is_going_down } ) {
        $heap->{ decency }->logger->debug3( "Child $child_pid has died, start new child fom parent" );
        $kernel->yield( "fork_child" ) if exists $heap->{ server };
    }
}

sub forking_catch_reload {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    
    if ( $heap->{ decency }->is_child ) {
        $heap->{ decency }->reload();
    }
    else {
        foreach my $child_pid( keys %{ $heap->{ childs } } ) {
            $heap->{ decency }->logger->debug3( "Got child: $child_pid" );
            kill USR2 => $child_pid;
        }
    }
    
    # say good night
    $kernel->sig_handled();
}


=head2 forking_new_connection

New connection etablished

=cut

sub forking_new_connection {
    my $heap = $_[ HEAP ];
    $heap->{ class }->create_handler( @_ );
}


=head2 forking_client_error

Error cleint ..

=cut

sub forking_client_error {
    my ( $kernel, $heap, $session, @args ) = @_[ KERNEL, HEAP, SESSION, ARG0..ARG9 ];
}


=head2 init_factory_args

Can be overwritten by childs

Returns additional args for create the factory

=cut

sub init_factory_args { return () }



=head2 cleanup_client

=cut

sub cleanup_client {
    my ( $heap, $session, $msg, $wait_finished ) = @_;
    my $name = __id_name( $heap, $session );
    $msg = $msg ? " after $msg" : "";
    
    if ( $wait_finished && ( ! delete $heap->{ finished } || ! $heap->{ client } ) ) {
        $heap->{ logger }->debug3( "Cleanup$msg but still waiting for finish $name" );
        return;
    }
    
    # check client wheel
    $heap->{ logger }->debug3( "Cleanup client connection $name$msg" );
    return unless defined $heap->{ client };
    
    # remove client (instance of POE::Wheel::ReadWrite.. will close socket)
    eval { delete $heap->{ client } };
    $heap->{ logger }->debug3( "Error cleaning connection $name$msg: $@" ) if $@;
    
    return;
}



=head2 handle_conn_error

=cut

sub handle_conn_error {
    my ( $heap, $session , $operation, $errnum, $errstr) = @_;
    
    my $name = __id_name( $heap, $session );
    
    # disconnect or reset ..
    my $cleanup_msg;
    if ( $operation eq 'read' && ( $errnum == 0 || $errnum == 104 ) ) {
        $heap->{ logger }->debug3( "Postfix closed connection" );
        $cleanup_msg = 'CLOSE';
    }
    
    # real error ..
    else {
        my $err = __id_name( $heap, $session, "OP: $operation, ERRNUM: $errnum, ESTR: $errstr" );
        $heap->{ logger }->error( "Weird disconnection from postfix $err" );
        $cleanup_msg = 'ERROR';
    }
    
    # close all sockets ..
    cleanup_client( $heap, $session, $cleanup_msg );
    
    # flush socket anywa
    eval { $heap->{ socket }->flush };
    $heap->{ logger }->error( "Could not flush socket after $cleanup_msg $name: $@" )
        if $@;
    
    return;
}


=head2 cleanup_stop

Cleanup by closing actual socket, removing socket and server from heap to delete all references

Called from ::SMTP and ::Postfix after connection closed .. 

=cut

sub cleanup_stop {
    my ( $heap, $session ) = @_;
    
    my $name = __id_name( $heap, $session );
    
    # >>>>>>>>>>>>> TODO <<<<<<<<<<<<<<<<<<
    #           ALSO FOR SERVER ?????
    # >>>>>>>>>>>>> TODO <<<<<<<<<<<<<<<<<<
    if ( $heap->{ socket } ) {
        $heap->{ logger }->debug3( "Close socket $name" );
        eval { close $heap->{ socket } };
        $heap->{ logger }->error( "Could not close socket $name: $@" ) if $@;
        eval { delete $heap->{ socket } };
        $heap->{ logger }->error( "Could not remove socket $name: $@" ) if $@;
    }
    
    return;
}


=head2 client_start

Starts a client

=cut

sub client_start {
    my ( $type, $filter, $kernel, $session, $heap ) = @_;
    
    # tell the parent session we are here
    $SESSIONS{ $session->ID } = $session;
    $kernel->signal( $heap->{ parent }, "new_client_session", $session );
    
    # start new r/w on the socket
    $heap->{ client } = POE::Wheel::ReadWrite->new(
        Handle       => $heap->{ socket },
        Filter       => $filter,
        InputEvent   => "${type}_input",
        ErrorEvent   => "${type}_error",
        FlushedEvent => "${type}_flush",
    );
    
    my $name = __id_name( $heap, $session );
    $heap->{ logger }->debug3( "Inited new connection from client $name" );
    
    return;
}


sub __id_name {
    my ( $heap, $session, @add ) = @_;
    my @n;
    push @n, "WID: ". ( defined $heap->{ client  }
        ? $heap->{ client }->ID
        : "NO"
    );
    push @n, "SID: ". $session->ID
        if $session;
    push @n, "PEER: ". $heap->{ peer_addr }. ":". $heap->{ peer_port }
        if defined $session;
    return "(". join( ", ", @n, @add ). ")";
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

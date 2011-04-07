package Mail::Decency::Core::Stats;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use Data::Dumper;
use DateTime;
use Mail::Decency::Helper::IntervalParse qw/ interval_to_int /;

=head1 NAME

Mail::Decency::Core::Stats

=head1 DESCRIPTION

Statistics logging for server and modules.

The intervals for the statistics can be multiple of hour, day, week, month and year.

For servers, it stores the final state of the filtered mails, so you can evaluate how many spam mails you retreive.

For modules there are two databases:

B<module_performance>: makes statistics about amount of modules calls, average scoring and average runtime (to evaluate how often a module is used, how long it takes and what it does)

B<module_results>: makes statistics of return results of the modules, so you can determine which modules needs to be adjusted.

=head1 CLASS ATTRIBUTES

=head2 enable_module_stats

Wheter any module stat is enabled

=cut

has enable_module_stats => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 enable_server_stats

Wheter any server stat is enabled

=cut

has enable_server_stats => ( is => 'rw', isa => 'Bool', default => 0 );

=head2 stats_enabled

Hashref of enabled/disabled stat names

=cut

has stats_enabled => ( is => 'rw', isa => 'HashRef[Bool]', default => sub { {
    final_state        => 1,
    module_performance => 1,
    module_results     => 1,
} } );

=head2 stats_intervals

Intervals for stats

=cut

has stats_intervals => ( is => 'rw', isa => 'ArrayRef[Str]', default => sub {
    [ qw/ hour day week month year / ]
} );

=head2 maintenance_intervals

Amount of intervals to keep for each interval period

=cut

has maintenance_intervals => ( is => 'rw', isa => 'HashRef[Int]', default => sub { {
    hour  => 336, # 14 days
    day   => 60,
    week  => 52,
    month => 24,
    year  => 10
} } );

=head2 stats_time_zone

Time zone, defaults to local

=cut

has stats_time_zone => ( is => 'ro', isa => 'DateTime::TimeZone', default => sub {
    DateTime::TimeZone::Local->TimeZone();
} );


our %SCHEMA_MODULE_PERFORMANCE = (
    module      => [ varchar => 32 ],
    period      => [ varchar => 10 ],
    start       => 'integer',
    calls       => 'integer',
    score       => 'integer',
    runtime     => 'real',
    last_update => 'integer',
    -unique     => [ qw/ module period start / ],
    -index      => [ qw/ start / ]
);

our %SCHEMA_MODULE_RESULTS = (
    module      => [ varchar => 32 ],
    period      => [ varchar => 10 ],
    status      => [ varchar => 32 ],
    start       => 'integer',
    calls       => 'integer',
    last_update => 'integer',
    -unique     => [ qw/ module period status start / ],
    -index      => [ qw/ start / ]
);

our %SCHEMA_FINAL_STATE = (
    period  => [ varchar => 25 ],
    status  => [ varchar => 10 ],
    start   => 'integer',
    amount  => 'integer',
    -unique => [ qw/ period status start / ],
    -index  => [ qw/ start / ]
);


=head1 MODIFIER

=head2 init

Update schema definition of this module

=cut

after 'init' => sub {
    my ( $self ) = @_;
    
    my $prefix = $self->name;
    
    # check which stats are enabled
    if ( my $stats_ref = $self->config->{ stats } ) {
        
        # get/set intervals
        my @intervals = @{ $stats_ref->{ intervals } ||= $self->stats_intervals };
        $self->stats_intervals( \@intervals );
        
        # get/set maintenance
        $stats_ref->{ maintenance } ||= {
            intervals => $self->maintenance_intervals
        };
        
        # .. for all interval stats
        my $interval_maintenance_ref
            = $stats_ref->{ maintenance }->{ intervals } || $self->maintenance_intervals;
        $self->maintenance_intervals( $interval_maintenance_ref );
        
        # read enabled state
        my %stat_types = (
            module => [ qw/ module_results module_performance / ],
            server => [ qw/ final_state / ]
        );
        
        # get / set enable stats
        my $enable_ref = {
            map { ( $_ => 1 ) }
            @{ $stats_ref->{ enable } || [ keys %{ $self->stats_enabled } ] }
        };
        my $set_enabled_ref = {};
        while( my ( $type, $ref ) = each %stat_types ) {
            my $type_method = "enable_${type}_stats";
            
            foreach my $stat( @$ref ) {
                $set_enabled_ref->{ $stat } = 0;
                next unless $enable_ref->{ $stat };
                
                $self->$type_method( 1 );
                $set_enabled_ref->{ $stat } = 1;
            }
        }
        $self->stats_enabled( $set_enabled_ref );
        $self->logger->debug3( "Stats inited: ". join( " / ", map {
            sprintf( '%s=%s', $_, $set_enabled_ref->{ $_ } );
        } keys %$set_enabled_ref ) );
    }
    
    my %schema;
    
    #
    # PER MODULE
    #
    
    # performance of modules, logs #calls, avg(runtime) ...
    if ( $self->stats_enabled->{ module_performance } ) {
        $schema{ $self->name. "_performance" } = \%SCHEMA_MODULE_PERFORMANCE;
        # $self->register_hook( post_module => sub {
        #     my ( $server ) = @_;
        # } );
    }
    
    # performance of modules, logs #calls, avg(runtime) ...
    if ( $self->stats_enabled->{ module_results } ) {
        $schema{ $self->name. "_results" } = \%SCHEMA_MODULE_RESULTS;
        
        # for policy
        # $self->register_hook( finish => sub {
        #     my ( $server, undef, $status, $final_code ) = @_;
        #     $server->update_server_stats( $status );
        # } );
        
        # for content filter
        # $self->register_hook( post_finish => sub {
        #     my ( $server, undef, $status, $final_code ) = @_;
        #     $server->update_server_stats( $status );
        # } );
    }
    
    
    #
    # SERVER WIDE
    #
    
    # logs final state (spam, ok, drop, ..)
    $schema{ $self->name. "_final_state" } = \%SCHEMA_FINAL_STATE
        if $self->stats_enabled->{ final_state };
    
    
    
    # set schema ..
    $self->{ schema_definition }->{ stats } = \%schema;
};


=head2 maintenance

Clears all entries which are older then the current interval. For hour, that would mean any hourly stats before the current hour, for year that would mean any stat from the last year and so on..

=cut

before 'maintenance' => sub {
    my ( $self ) = @_;
    
    $self->logger->info( "Cleanup old stats (final_state, performance, results)" );
    
    my $table = lc( $self->name );
    my $now = DateTime->now( time_zone => $self->stats_time_zone );
    
    #
    # CLEAR OTHER
    #   based on amount of intervals
    #
    my $maintenance_interval_ref = $self->maintenance_intervals;
    foreach my $stat( qw/ final_state module_performance module_results / ) {
        
        $self->logger->info( "Cleanup for $stat" );
        
        # all intervals ..
        foreach my $interval( @{ $self->stats_intervals } ) {
            
            # get latest allowed date (all before will be removed)
            my $amount_intervals = $maintenance_interval_ref->{ $interval } || 1;
            my $start = $now->clone->truncate( to => $interval )
                ->add( "${interval}s" => -1 * $amount_intervals );
            
            # count obsolete
            ( my $name = $stat ) =~ s/^module_//;
            $self->__count_and_remove( $table => $name => {
                start  => { '<' => $start->epoch },
                period => $interval
            }, {
                start  => { '>=' => $start->epoch },
                period => $interval
            }, '  Remove %d, keep %d entries in '. $stat. ' for interval '. $interval );
        }
    }
};


=head1 METHODS

=head2 update_module_stats

Updates module wise performance tables 

=cut

sub update_module_stats {
    my ( $self, $module, $status, $score_diff, $runtime ) = @_;
    return unless $self->enable_module_stats;
    
    
    my $now = DateTime->now( time_zone => $self->stats_time_zone );
    my @intervals = map {
        my $iv = $now->clone->truncate( to => $_ );
        [ $_, $iv->epoch ];
    } grep {
        /^(hour|day|week|month|year)$/
    } @{ $self->stats_intervals };
    
    eval {
        my $table = lc( $self->name );
        
        foreach my $interval_ref( @intervals ) {
            my %search = (
                module => "$module",
                period => $interval_ref->[0],
                start  => $interval_ref->[1],
            );
            
            if ( $self->stats_enabled->{ module_performance } ) {
                $self->database->usr_lock;
                my $db_ref = $self->database->get( stats => "${table}_performance" => \%search );
                $db_ref ||= { score => 0, runtime => 0, calls => 0 };
                $self->database->set( stats => "${table}_performance" => \%search, {
                    score       => ( $db_ref->{ score } || 0 ) + $score_diff,
                    calls       => $db_ref->{ calls } + 1,
                    runtime     => ( $db_ref->{ runtime } || 0 ) + $runtime,
                    last_update => time()
                } );
                $self->database->usr_unlock;
            }
            
            if ( $self->stats_enabled->{ module_results } ) {
                $search{ status } = $status;
                $self->database->increment( stats => "${table}_results" => \%search, {
                    key         => 'calls',
                    last_update => 1
                } );
            }
        }
    };
    $self->logger->error( "Error updating stats for $module / $status: $@" ) if $@;
    
    return;
}


=head2 update_server_stats

Updates server wide  state logs.

=cut

sub update_server_stats {
    my ( $self, $state ) = @_;
    return unless $self->enable_server_stats;
    
    my $table = lc( $self->name );
    
    #
    # UPDATE FINAL STATES
    #
    
    if ( $self->stats_enabled->{ final_state } ) {
        my $now = DateTime->now( time_zone => $self->stats_time_zone );
        my @intervals = map {
            my $iv = $now->clone->truncate( to => $_ );
            [ $_, $iv->epoch ];
        } grep {
            /^(hour|day|week|month|year)$/
        } @{ $self->stats_intervals };
        
        eval {
            
            foreach my $interval_ref( @intervals ) {
                
                # increment
                $self->database->increment( stats => "${table}_final_state" => {
                    period => $interval_ref->[0],
                    start  => $interval_ref->[1],
                    status => $state
                }, {
                    key => 'amount'
                } );
            }
        };
        $self->logger->error( "Error updating servers stats: $@" ) if $@;
    }
    
    return;
}


=head2 print_stats

Print out stats

=cut

sub print_stats {
    my ( $self, $return ) = @_;
    
    my $table = lc( $self->name );
    
    my $now = DateTime->now( time_zone => $self->stats_time_zone );
    my @intervals = map {
        my $iv = $now->clone->truncate( to => $_ );
        [ $_, $iv->epoch ];
    } grep {
        /^(hour|day|week|month|year)$/
    } @{ $self->stats_intervals };
    
    my @module_names = map { "$_" } @{ $self->childs };
    ( my $server_name = ref( $self ) ) =~ s/^.*:://;
    push @module_names, "${server_name}Core";
    
    my ( %stats_weight, %stats_response ) = ();
    
    foreach my $interval_ref( @intervals ) {
        my ( $period, $start ) = @$interval_ref;
        
        foreach my $module( @module_names ) {
            my $weight_ref = $self->database->get( stats => "${table}_performance" => {
                module => $module,
                period => $period,
                start  => { 
                    '>=' => $start,
                }
            } );
            if ( $weight_ref ) {
                $stats_weight{ $module } ||= {};
                $stats_weight{ $module }->{ $period } = $weight_ref->{ weight };
                
                if ( $period eq 'year' ) {
                    $stats_weight{ $module }->{ $_ } = $weight_ref->{ $_ }
                        for qw/ calls runtime /;
                }
            }
            
            my @response = $self->database->search( stats => "${table}_response" => {
                module => $module,
                period => $period,
                start  => {
                    '>=' => $start,
                }
            } );
            
            foreach my $response_ref( @response ) {
                next unless $response_ref->{ type };
                $stats_response{ $response_ref->{ type } } ||= {};
                $stats_response{ $response_ref->{ type } }->{ $module } ||= {};
                $stats_response{ $response_ref->{ type } }->{ $module }->{ $period }
                    = $response_ref->{ data };
            }
        }
    }
    
    my $format = '%-20s'. ( ' | %-10s' x 5 );
    
    
    #
    # PRINT RESPONSE
    #
    
    if ( scalar keys %stats_response ) {
        
        print "# **************************************\n# RESPONSE STATS\n# **************************************\n";
        foreach my $response( sort keys %stats_response ) {
            my @out = ( sprintf( $format, 'Module', map { ucfirst( $_ ). " ". $now->$_ } qw/ hour day week month year / ) );
            
            print "\n# ****** $response ******\n";
            
            my $response_ref = $stats_response{ $response };
            foreach my $module( sort { $b =~ /Core$/ ? -1 : $a cmp $b } keys %$response_ref ) {
                push @out, sprintf( $format, $module,
                    $response_ref->{ $module }->{ hour }
                        ? sprintf( '%.1f', $response_ref->{ $module }->{ hour } )
                        : "-"
                    ,
                    $response_ref->{ $module }->{ day }
                        ? sprintf( '%.1f', $response_ref->{ $module }->{ day } )
                        : "-"
                    ,
                    $response_ref->{ $module }->{ week }
                        ? sprintf( '%.1f', $response_ref->{ $module }->{ week } )
                        : "-"
                    ,
                    $response_ref->{ $module }->{ month }
                        ? sprintf( '%.1f', $response_ref->{ $module }->{ month } )
                        : "-"
                    ,
                    $response_ref->{ $module }->{ year }
                        ? sprintf( '%.1f', $response_ref->{ $module }->{ year } )
                        : "-"
                    ,
                );
            }
            
            print join( "\n", @out ). "\n";
        }
        print "\n\n";
    }
    
    #
    # PRINT WEIGHT
    #
    if ( scalar keys %stats_weight ) {
        
        print "# **************************************\n# WEIGHT STATS\n# **************************************\n";
        my @out = ( sprintf( $format, 'Module', map { ucfirst( $_ ). " ". $now->$_ } qw/ hour day week month year / ) );
        
        foreach my $module( sort { $b =~ /Core$/ ? -1 : $a cmp $b } keys %stats_weight ) {
            push @out, sprintf( $format, $module,
                $stats_weight{ $module }->{ hour }
                    ? sprintf( '%.1f', $stats_weight{ $module }->{ hour } )
                    : "-"
                ,
                $stats_weight{ $module }->{ day }
                    ? sprintf( '%.1f', $stats_weight{ $module }->{ day } )
                    : "-"
                ,
                $stats_weight{ $module }->{ week }
                    ? sprintf( '%.1f', $stats_weight{ $module }->{ week } )
                    : "-"
                ,
                $stats_weight{ $module }->{ month }
                    ? sprintf( '%.1f', $stats_weight{ $module }->{ month } )
                    : "-"
                ,
                $stats_weight{ $module }->{ year }
                    ? sprintf( '%.1f', $stats_weight{ $module }->{ year } )
                    : "-"
                ,
                
            );
        }
        print join( "\n", @out ). "\n\n\n";
    }
    
    #
    # PRINT RUNTIME
    #
    if ( scalar keys %stats_weight ) {
        
        print "# **************************************\n# RUNTIME STATS\n# **************************************\n";
        my @out = ( sprintf( $format, 'Module', map { ucfirst( $_ ) } qw/ total calls average - - / ) );
        
        foreach my $module( sort { $b =~ /Core$/ ? -1 : $a cmp $b } keys %stats_weight ) {
            my $average = $stats_weight{ $module }->{ calls } > 0
                ? $stats_weight{ $module }->{ runtime } / $stats_weight{ $module }->{ calls }
                : 0
            ;
            push @out, sprintf( $format, $module,
                sprintf( '%.2f', $stats_weight{ $module }->{ runtime } || 0 ),
                $stats_weight{ $module }->{ calls } || "-",
                sprintf( '%.4f', $average ),
                "-",
                "-",
            );
        }
        print join( "\n", @out ). "\n\n\n";
    }
    
    #
    # MODULE STATS
    #
    
    foreach my $module( @{ $self->childs } ) {
        next unless $module->can( 'print_stats' );
        print "# *************************************\n# Module: $module STATS\n# *************************************\n";
        $module->print_stats;
        print "\n\n\n";
    }
    
}



sub __count_and_remove {
    my ( $self, $table, $name, $search_ref, $search_reverse_ref, $log_out ) = @_;
    my $obsolete = $self->database->count( stats => "${table}_${name}" => $search_ref );
    my $ok = $self->database->count( stats => "${table}_${name}" => $search_reverse_ref );
    $self->logger->info( sprintf( $log_out, $obsolete, $ok ) );
    $self->database->remove( stats => "${table}_${name}" => $search_ref )
        unless $ENV{ DECENCY_MAINTENANCE_DRY_RUN };
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut




1;

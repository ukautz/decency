package Mail::Decency::Core::LiveStats;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

use mro 'c3';
use Data::Dumper;

our %DATE_FORMATS = (
    yearly   => '%Y',
    monthly  => '%Y-%mM',
    weekly   => '%Y-%UW',
    daily    => '%F',
    hourly   => '%F %H',
    minutely => '%F %H:%M',
);

=head1 NAME

Mail::Decency::Detective::LiveStats

=head1 DESCRIPTION

Base class for L<Mail::Decency::Detective::LiveStats> and L<Mail::Decency::Doorman::LiveStats>.

Save statistical informations about throuput in a database.

=head2 STREAM LOG

Stream log is a simple log containging: timestamp, from, to, subject

=head2 ACCUMULATIONS

Accumylations

=cut

=head1 CLASS ATTRIBUTES

=head2 stream_log : Bool

Enable/disable stream log.

=cut

has stream_log     => ( is => 'rw', isa => 'Bool', default => 1 );

=head2 set_header : HashRef

Set's a header. If exists, it will be overwritten.

=cut

has accumulate     => ( is => 'rw', isa => 'ArrayRef[HashRef[ArrayRef]]' );

=head2 update_live_stats

Increment accumulations, writes stream

=cut

sub update_live_stats {
    my ( $self, $status ) = @_;
    
    my $table = 'livestats_'. lc( $self->server->name );
    my $session = $self->session;
    
    #
    # STREAM
    #
    if ( $self->stream_log ) {
        my %subject = $self->can( 'mime' )
            ? ( subject => ( scalar $self->mime->head->get( 'Subject' ) ) || '' )
            : ()
        ;
        $self->database->set( $table => stream => {
            time    => time(),
            from    => $session->from,
            to      => $session->to,
            status  => $status,
            %subject
        } );
    }
    
    #
    # ACCUMULATIONS
    #
    if ( $self->accumulate ) {
        my %interval = ();
        my $dt = DateTime->now;
        
        
        #
        # DEFAULT ACCUMULATION
        #
        foreach my $period( map {
            $_ eq 'total'
                ? $_
                : $dt->strftime( $DATE_FORMATS{ $_ } )
        } qw/ total yearly monthly weekly daily / ) {
            
            $self->database->increment( $table => accumulate => {
                key    => 'total',
                value  => 'total',
                period => $period
            }, {
                last_update => 1
            } ) ;
            $self->database->increment( $table => accumulate => {
                key    => 'totalstatus',
                value  => $status,
                period => $period
            }, {
                last_update => 1
            } ) ;
        }
        
        #
        # CUSTOM ACCUMULATION
        #
        if ( ref( $self->accumulate ) eq 'ARRAY' ) {
            
            ACCUMULATES:
            foreach my $accumulate_ref( @{ $self->accumulate } ) {
                
                # get periods
                my @periods = map {
                    $_ eq 'total'
                        ? $_
                        : $dt->strftime( $DATE_FORMATS{ $_ } || DD::cop_it "Dunno period '$_'" )
                } @{ $accumulate_ref->{ periods } };
                
                
                # add content data
                my ( @keys, @values, %other ) = ();
                @values = map {
                    push @keys, $_;
                    $session->$_ || "";
                } grep {
                    $other{ $_ } ++ unless $session->can( $_ );
                    $session->can( $_ )
                } sort @{ $accumulate_ref->{ contents } };
                
                # status ?
                if ( $other{ status } ) {
                    push @keys, 'status';
                    push @values, $status;
                }
                
                my $key   = join( '|', @keys );
                next ACCUMULATES unless $key;
                
                my $value = join( '|', @values );
                
                foreach my $period( @periods ) {
                    $self->database->increment( $table => accumulate => {
                        key    => $key,
                        value  => $value,
                        period => $period
                    }, {
                        last_update => 1
                    } );
                }
            }
        }
    }
    
    return ;
}


=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

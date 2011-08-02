package Mail::Decency::Detective::LiveStats;

use Mouse;
extends qw/
    Mail::Decency::Detective::Core
/;
extends qw/
    Mail::Decency::Detective::Model::LiveStats
/;
with qw/
    Mail::Decency::Core::LiveStats
/;

use version 0.74; our $VERSION = qv( "v0.2.0" );

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

Save statistical informations about throuput in a database.

=head2 STREAM LOG

Stream log is a simple log containging: timestamp, from, to, subject

=head2 ACCUMULATIONS

Accumylations

=cut

=head1 CONFIG

    ---
    
    disable: 0
    #max_size: 0
    #timeout: 30
    
    # enable stream log
    stream_log: 1
    
    # user defined accumulations
    accumulate:
    
        # cumulate stats per sender domain and status (reject/delivered)
        -
            contents:
                - from_domain
                - status
            periods:
                - daily
                - weekly
                - monthy
                - yearly
                - total
                
        # cumulate stats per country and status .. only in "total" (over all time) period
        -
            contents:
                - country
                - status
            periods:
                - total
        
        # cumulate stats per sender_domain & recipient_domain daily
        -
            contents:
                - from_domain
                - to_domain
            periods:
                - daily
    


=head1 CLASS ATTRIBUTES

See L<Mail::Decency::Core::LiveStats>

=head1 METHODS

See L<Mail::Decency::Core::LiveStats>


=head2 init

=cut

sub init {
    my ( $self ) = @_;
    
    foreach my $meth( qw/
        stream_log
        accumulate
    / ) {
        $self->$meth( $self->config->{ $meth } )
            if defined $self->config->{ $meth };
    }
    
    DD::cop_it "Require at least stream_log or accumulate\n"
        if ! $self->stream_log && ! $self->accumulate;
    
}


=head2 hook_post_finish

=cut

sub hook_post_finish {
    my ( $self, $status, $final_code ) = @_;
    $self->update_live_stats( $status );
    return ( $status, $final_code );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

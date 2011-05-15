package Mail::Decency::Core::DatabaseCreate;

use Mouse::Role;

use version 0.74; our $VERSION = qv( "v0.2.0" );

=head1 NAME

Mail::Decency::Core::Meta::DatabaseCreate

=head1 DESCRIPTION

Prints SQL CREATE statements for module and server databases. Of course, only for DBD databases..

=head1 METHODS


=head2 print_sql

Print SQL "CREATE *" statements.

=cut

sub print_sql {
    my ( $self ) = @_;
    
    print "-- SQL START\n\n";
    
    foreach my $child( @{ $self->childs }, $self ) {
        next unless $child->can( 'schema_definition' );
        my $definition_ref = $child->schema_definition;
        print "-- For: $child\n";
        while( my ( $schema, $tables_ref ) = each %$definition_ref ) {
            while ( my ( $table, $columns_ref ) = each %$tables_ref ) {
                $child->database->setup( $schema => $table => $columns_ref,
                    { execute => 0, test => 0 } );
                print "\n";
            }
        }
        print "\n";
    }
    
    print "\n-- SQL END\n";
}


=head2 check_structure

=cut

sub check_structure {
    my ( $self, $update ) = @_;
    
    $self->setup();
    
    use Data::Dumper;
    CHECK_CHILDS:
    foreach my $child( @{ $self->childs }, $self ) {
        next unless $child->can( 'schema_definition' );
        my $definition_ref = $child->schema_definition;
        while( my ( $schema, $tables_ref ) = each %$definition_ref ) {
            while( my ( $table, $table_ref ) = each %$tables_ref ) {
                #next if ref( $child ) !~ /^Mail::Decency::[^:]+::/;
                #print Dumper( $table_ref );
                my $ok = 0;
                print "**** Check $schema / $table *****\n";
                
                my ( $missing_ref, $obsolete_ref, $errors_ref );
                eval {
                    ( $ok, $missing_ref, $obsolete_ref, $errors_ref ) = $child->database->check_table( $schema => $table => $table_ref, $update );
                };
                if ( $@ ) {
                    print "-- Failed to update $schema / $table for $child: $@\n";
                }
                elsif ( $ok == -1 ) {
                    print "-- Table $schema / $table does not exist, cannot check indexes\n";
                }
                elsif ( ! $ok ) {
                    print "-- Failed to create index, check table manually\n";
                    print "-- Missing or obsolete indexes in $schema / $table:\n";
                    print "    Missing:\n". join( "\n", map { sprintf( '    * %s', $_ ) } @$missing_ref ). "\n" if $#$missing_ref > -1;
                    print "    Obsolete:\n". join( "\n", map { sprintf( '    * %s', $_ ) } @$obsolete_ref ). "\n" if $#$obsolete_ref > -1;
                    print "    Errors: \n". join( "\n", map { sprintf( '    * %s', $_ ) } @$errors_ref ). "\n" if $#$errors_ref > -1;
                }
                else {
                    print "++ Table $schema / $table is good\n\n";
                }
                
                print "**********\n\n";
                
                #last CHECK_CHILDS;
            }
        }
    }
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

package MD_DB;

use strict;
use DBI;
use DBD::SQLite;
use FindBin qw/ $Bin /;

sub sqlite_file {
    my ( $no_setup ) = @_;
    
    my $file = $ENV{ SQLITE_FILE };
    unless ( $file ) {
        my $schema = $ENV{ DB_SCHEMA } || "schema";
        my $table  = $ENV{ DB_TABLE }  || "table";
        $file = "$Bin/data/sqlite.db";
        create_sqlite( "${schema}_${table}", $file, $no_setup );
    }
    return $file;
}

sub create_sqlite {
    my ( $table, $file, $no_setup ) = @_;
    
    if ( -f $file && ! $ENV{ NO_DB_CLEANUP } ) {
        unlink( $file );
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","");
    
    unless ( $no_setup ) {
        my $sql = <<SQL;
CREATE TABLE $table (
    something VARCHAR( 50 ),
    data INT,
    data2 INT
    last_update INT
);
SQL
        my $sth = $dbh->prepare( $sql ); 
        $sth->execute();
    }
    
    
    $dbh->disconnect;
    return ;
}



1;

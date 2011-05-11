#!/usr/bin/perl

use strict;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use Test::More;

use Mail::Decency::Helper::Database;
use MD_DB;
use MD_Misc;
use Data::Dumper;

plan tests => 3;

$ENV{ NO_DB_DISCONNECT } = 1;
my $db_tests = 14;
my $server = DummyServer->new();

SKIP: {
    
    skip "DBD::SQLite not installed, skipping tests", 1 unless eval "use DBD::SQLite; 1;";
    skip "Skipping DBD Test", 1 if $ENV{ SKIP_DBD };
    
    subtest "DBD::SQLite" => sub {
        plan tests => $db_tests + 2;
        
        # get mongo connection
        my %create;
        my $file = MD_DB::sqlite_file( 1 );
        $create{ args } = [ "dbi:SQLite:dbname=$file" ];
        
        my $db = eval { test_db( "DBD", $server, %create ) }
            or diag( "Error Test: $@" );
        unlink $file unless $ENV{ NO_DB_CLEANUP };
        
        eval { $db->disconnect(); };
        ok( ! $@, "Cleanup test database" ) or diag( "Error Cleanup: $@" );
    };
};

SKIP: {
    
    skip "MongoDB not installed or to old (require >= 0.35), skipping tests", 1 unless eval "use MongoDB 0.35; 1;";
    skip "MongoDB tests, set USE_MONGODB=1, MONGODB_DATABASE to the database (default: test_decency, will be dropped afterwards), MONGODB_HOST to the host to be used (default: 127.0.0.1) and MONGODB_PORT to the port to be used (default: 27017) in Env to enable", 1 unless $ENV{ USE_MONGODB };
    
    subtest "MongoDB" => sub {
        plan tests => $db_tests + 2;
        
        # get mongo connection
        my %create;
        $create{ database } = $ENV{ MONGODB_TEST_DATABASE } || 'decency_test';
        $create{ host } = $ENV{ MONGODB_HOST } if $ENV{ MONGODB_HOST };
        $create{ port } = $ENV{ MONGODB_PORT } if $ENV{ MONGODB_PORT };
        
        my $db = eval { test_db( "MongoDB", $server, %create ) }
            or diag( "Error in test: $2" );
        
        unless ( $ENV{ NO_DB_CLEANUP } ) {
            eval { $db->db->drop(); };
        }
        ok( ! $@, "Cleanup test database" ) or diag( "Error Cleanup: $@" );
        
    };
};

SKIP: {
    
    skip "Net::LDAP not installed, skipping tests", 1 unless eval "use Net::LDAP; 1;";
    skip <<'LDAP', 1 unless $ENV{ USE_LDAP };
Net::LDAP tests, set:
* USE_LDAP=1 to enable
* LDAP_HOST to the host (default: localhost:389)
* LDAP_USER to bind-user (default: empty)
* LDAP_PASSWORD to the bind-password (default: empty)
* LDAP_SCHEME to 'ldap', 'ldaps' or 'ldapi' (default: ldap)
* LDAP_BASE to your base (default: dc=nodomain)

You also need to install the following schema for testing:

attributetype ( 1.1.9999.100.1 NAME 'decencySchemaTableSomething'
    EQUALITY caseIgnoreMatch
    ORDERING caseIgnoreOrderingMatch
    SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{255} SINGLE-VALUE )

attributetype ( 1.1.9999.100.2 NAME 'decencySchemaTableData'
    EQUALITY integerMatch
    ORDERING integerOrderingMatch
    SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )

attributetype ( 1.1.9999.100.3 NAME 'decencySchemaTableData2'
    EQUALITY integerMatch
    ORDERING integerOrderingMatch
    SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )

attributetype ( 1.1.9999.100.4 NAME 'decencySchemaTableLastUpdate'
    EQUALITY integerMatch
    ORDERING integerOrderingMatch
    SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )

objectclass ( 1.1.9999.101.1 NAME 'decencySchemaTable'
    SUP top STRUCTURAL
    MUST ( cn $ decencySchemaTableSomething $ decencySchemaTableData $ decencySchemaTableData2 $ decencySchemaTableLastUpdate ) )

LDAP
    
    subtest "LDAP" => sub {
        plan tests => $db_tests + 2;
        
        # get mongo connection
        my %create;
        $create{ host } = $ENV{ LDAP_HOST } || 'localhost:389';
        $create{ base } = $ENV{ LDAP_BASE } || 'dc=nodomain';
        $create{ user } = $ENV{ LDAP_USER } if $ENV{ LDAP_USER };
        $create{ password } = $ENV{ LDAP_PASSWORD } if $ENV{ LDAP_PASSWORD };
        $create{ scheme } = $ENV{ LDAP_SCHEME } if $ENV{ LDAP_SCHEME };
        
        my $db = eval { test_db( "LDAP", $server, %create ) }
            or diag( "Error in test: $@" );
        
        eval {
            my $res = $db->db->search(
                base   => 'ou=schema,'. $create{ base },
                scope  => 'sub',
                filter => 'objectClass=*'
            );
            while( my $item = $res->pop_entry ) {
                $db->db->delete( $item->dn );
            }
        };
        ok( ! $@, "Cleanup test database" ) or diag( "Error Cleanup: $@" );
        
    };
};






sub test_db {
    my ( $type, $server, %create ) = @_;
    
    my ( $sem, $sem_err ) = get_semaphore();
    die "Sem error: $sem_err" if $sem_err;
    $create{ locker } = $sem;
    $create{ locker_pid } = $$;
    $create{ logger } = empty_logger();
    my $db = Mail::Decency::Helper::Database->create( $type => \%create );
    my $schema = $ENV{ DB_SCHEMA } || "schema";
    my $table  = $ENV{ DB_TABLE }  || "table";
    $db->setup( $schema => $table, {
        something   => [ varchar => 255 ],
        data        => 'integer',
        data2       => 'integer',
        last_update => 'integer',
        -unique     => [ 'something' ]
    }, { execute => 1, test => 1, register => 1 } );
    ok( $db->ping( $schema => $table ), "Database setup" )
        or skip( "Could not setup database $type: $schema => $table", 12 );
    
    # fetch null-data
    my $value = 'there-'. time();
    my $ref = $db->get( $schema => $table => {
        something => $value
    } );
    ok( !$ref, "Not existing data not found" );
    
    # create data
    eval {
        $db->set( $schema => $table => {
            something => $value,
        } );
    };
    ok( !$@, "Data created" )
        or fail( "Error: $@" );
    
    # re-read data
    $ref = $db->get( $schema => $table => {
        something => $value
    } );
    ok(
        $ref && ref( $ref ) eq "HASH" && defined $ref->{ something } && $ref->{ something } eq $value,
        "Data fetched"
    );
    
    # increment
    $db->increment( $schema => $table => {
        something => $value
    } );
    my $incr_val = $db->increment( $schema => $table => {
        something => $value
    } );
    ok( $incr_val == 2, "Increment data colum" )
        or diag( "Found increment value of $incr_val, expecting 2" );
    
    # extended increment
    my $before_incr = time();
    $db->increment( $schema => $table => {
        something => $value
    }, {
        amount      => 3,
        last_update => 1,
        key         => 'data2'
    } );
    $ref = $db->get( $schema => $table => {
        something => $value
    } );
    ok(
        $ref && $ref->{ last_update }
        && $ref->{ last_update } <= time()
        && $ref->{ last_update } >= $before_incr
        && $ref->{ data } == 2
        && $ref->{ data2 } == 3,
        "Advanced increment (key, last_update, amount)"
    );
    
    # count data
    foreach my $num( 0..8 ) {
        $db->set( $schema => $table => {
            something => $num. '-'. $value
        } );
    }
    my $count = $db->count( schema => table => {} );
    ok( $count == 10, "Count entries" )
        or diag( "Found $count, supposed to find 10" );
    $count = $db->count( schema => table => {
        something => [ $value, "0-$value" ]
    } );
    ok( $count == 2, "Count entries with query" )
        or diag( "Found $count, supposed to find 2" );
        
    
    # multi set
    $ENV{ DBG } = 1;
    $db->set( $schema => $table => {}, { data => 33 }, { update_all => 1 } );
    my $ok_set = 0;
    my ( $handle, $meth ) = $db->search_read( $schema => $table );
    while( my $item = $handle->$meth ) {
        $ok_set++ if $item->{ data } == 33;
    }
    $db->set( $schema => $table => {
        something => 'singleentry'
    }, { data => 99 } );
    my $ok_single = 0;
    ( $handle, $meth ) = $db->search_read( $schema => $table );
    while( my $item = $handle->$meth ) {
        $ok_single++ if $item->{ data } == 99;
    }
    ok( $ok_set == 10 && $ok_single == 1, "Multi set" );
    
    # get distinct
    my @distinct1 = $db->distinct( schema => table => {}, 'something' );
    my $counter = 0;
    foreach my $num( 0..8 ) {
        $db->set( $schema => $table => {
            something => $num. '-'. $value
        }, {
            data => $counter++
        } );
    }
    
    my @res = $db->search( $schema => $table, {}, { order => [ {
        col => 'something',
        dir => 'asc'
    } ], offset => 3, limit => 5 } );
    my $ok_offset = 0;
    my $offset_compare = 2;
    foreach my $ref( @res ) {
        $ok_offset ++
            if $ref->{ something } =~ /^$offset_compare\-/;
        $offset_compare++;
    }
    if ( $ok_offset == 5 ) {
        warn "    Sort works fine\n";
    }
    else {
        warn "    Sort does not work\n";
    }
    
    # re-read 
    my @distinct2 = $db->distinct( schema => table => {}, 'something' );
    
    # other column
    my @distinct3 = $db->distinct( schema => table => {}, 'data' );
    ok( scalar @distinct1 == scalar @distinct2 && scalar @distinct2 == 11, "Distinct columns" );
    
    # search extended
    my $val = 1000;
    foreach my $num( 20..24 ) {
        $db->set( $schema => $table => {
            something => $num. '-'. $value,
            data      => $val
        } );
        $db->set( $schema => $table => {
            something => $num. '-'. $value. '-negative',
            data      => -1 * $val
        } );
        $val += 10;
    }
    my $count_res1 = $db->count( $schema => $table => {
        data => { '>' => 1010 }
    } );
    ok( $count_res1 == 3, 'Extended search: greater than' )
        or fail( "Expected 3, found $count_res1" );
    my $count_res2 = $db->count( $schema => $table => {
        data => { '<' => -1010 }
    } );
    ok( $count_res2 == 3, 'Extended search: lower than' )
        or fail( "Expected 3, found $count_res2" );
    $db->set( $schema => $table => {
        something => 'something-999-123',
        data      => 999,
        data2     => 123
    } );
    $db->set( $schema => $table => {
        something => 'something-999-124',
        data      => 999,
        data2     => 124
    } );
    my $count_res3 = $db->count( $schema => $table => {
        data  => 999,
        data2 => { '!=' => 124 }
    } );
    ok( $count_res3 == 1, 'Extended search: not equal' )
        or fail( "Expected 1, found $count_res3" );
    my $count_res4 = $db->count( $schema => $table => {
        data2 => [ 124, 123 ]
    } );
    ok( $count_res4 == 2, 'Extended search: or' )
        or fail( "Expected 2, found $count_res4" );
    
    
    # remove data
    $db->remove( $schema => $table => {
        something => $value
    } );
    $ref = $db->get( $schema => $table => {
        something => $value
    } );
    ok( !$ref, "Data has been removed" );
    
    return $db;
}

package DummyServer;

sub new {
    return bless {
        cache => DummyCache->new
    }, $_[0];
}

sub cache {
    shift->{ cache }
}

sub do_lock      {}
sub do_unlock    {}
sub read_lock    {}
sub read_unlock  {}
sub write_lock   {}
sub write_unlock {}
sub usr_lock     {}
sub usr_unlock   {}

package DummyCache;

sub new {
    return bless {
        data => {},
    }, $_[0];
}

sub get {
    my ( $self, $key ) = @_;
    $self->{ data }->{ $key };
}

sub set {
    my ( $self, $key, $val ) = @_;
    return $self->{ data }->{ $key } = $val; 
}

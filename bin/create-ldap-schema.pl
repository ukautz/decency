#!/usr/bin/perl


use strict;
use warnings;
use FindBin qw/ $Bin /;

BEGIN {
    
    # check all available dirs
    foreach my $dir( ( '/opt/decency/lib', '/opt/decency/locallib', "$Bin/../lib" ) ) {
        -d $dir && eval 'use lib "'. $dir. '"';
    }
    
    # try load local lib also
    eval 'use local::lib';
}

use Data::Dumper;
use Mail::Decency::Core::Excludes;
use Mail::Decency::Core::CustomScoring;
use Mail::Decency::Core::Stats;

my $core_oid = '99.1';
my @core_schemas = ( {
    name  => '%s_exclusions',
    oid   => '99.2',
    table => \%Mail::Decency::Core::Excludes::EXCLUDES_TABLE
}, {
    name  => '%s_custom_scoring',
    oid   => '99.3',
    table => \%Mail::Decency::Core::CustomScoring::CUSTOM_SCORING_TABLE
}, {
    name  => 'stats_%s_performance',
    oid   => '99.4.1',
    table => \%Mail::Decency::Core::Stats::SCHEMA_MODULE_PERFORMANCE
}, {
    name  => 'stats_%s_results',
    oid   => '99.4.2',
    table => \%Mail::Decency::Core::Stats::SCHEMA_MODULE_RESULTS
}, {
    name  => 'stats_%s_final_state',
    oid   => '99.4.3',
    table => \%Mail::Decency::Core::Stats::SCHEMA_FINAL_STATE
} );



my @module_models = (
    [ qw/
        100.1
        Policy::CBL
    / ],
    [ qw/
        100.2
        Policy::CWL
    / ],
    [ qw/
        100.3
        Policy::GeoWeight
    / ],
    [ qw/
        100.4
        Policy::Greylist
    / ],
    [ qw/
        100.5
        Policy::Honeypot
    / ],
    [ qw/
        100.6
        Policy::SenderPermit
    / ],
    [ qw/
        100.7
        Policy::Throttle
    / ],
);

my %type_map = (
    varchar => [
        '1.3.6.1.4.1.1466.115.121.1.15', # DirectoryString syntax
        'caseIgnoreMatch',               # match
        'caseIgnoreOrderingMatch',       # ordering
        'decencyVarchar%d',              # name
        "${core_oid}.1",
    ],
    integer => [
        '1.3.6.1.4.1.1466.115.121.1.27', # syntax
        'integerMatch',                  # match
        'integerOrderingMatch',          # match
        'decencyInteger',                # name
        "${core_oid}.2",
    ],
    text => [
        '1.3.6.1.4.1.1466.115.121.1.15', # DirectoryString syntax
        'caseIgnoreMatch',               # match
        'caseIgnoreOrderingMatch',       # ordering
        'decencyText',                   # name
        "${core_oid}.3",
    ],
    real => [
        '1.3.6.1.4.1.1466.115.121.1.27', # Integer syntax .. implementation takes care of the rest
        'integerMatch',                  # match
        'integerOrderingMatch',          # ordering
        'decencyReal',                   # name
        "${core_oid}.4",
    ]
    
);

my ( @create_prime, @create_sub, @create_class, %cache, %counter, $counter_cache );


#
# MODULE MODELS
#

foreach my $module_ref( @module_models ) {
    my ( $oid_base, $name ) = @$module_ref;
    my ( $class_name, $module_name ) = split( /::/, $name );
    my $module_class = "Mail::Decency::${class_name}::Model::${module_name}";
    eval "use $module_class";
    my $module = $module_class->new();
    my $definition_ref = $module->schema_definition();
    
    foreach my $schema( sort keys %$definition_ref ) {
        my $schema_ref = $definition_ref->{ $schema };
        foreach my $table( sort keys %$schema_ref ) {
            my $table_ref = $schema_ref->{ $table };
            my $unique_ref = delete $table_ref->{ -unique } || [];
            my $index_ref = delete $table_ref->{ -index } || [];
            my @must = ();
            foreach my $column( sort keys %$table_ref ) {
                next if index( $column, '-' ) == 0;
                my $attrib_type = _attrib_name( $table_ref->{ $column } );
                
                my $ldap_column = _name( $schema, $table, $column );
                push @create_sub, [ "$oid_base.2", $ldap_column, $attrib_type ];
                push @must, $ldap_column;
            }
            
            push @create_class, [ "$oid_base.1", _name( $schema, $table ), \@must ];
        }
    }
}


#
# ADD EXCLUSIONS AND CUSTOM SCORING
#

foreach my $server_ref( [ ContentFilter => 1 ], [ Policy => 2 ] ) {
    my ( $server, $num ) = @$server_ref;
    
    foreach my $core_ref( @core_schemas ) {
        my $count = 10;
        my $oid = $core_ref->{ oid }. '.'. $num;
        my $prefix_name = sprintf( $core_ref->{ name }, lc( $server ) );
        my @must;
        foreach my $key( sort keys %{ $core_ref->{ table } } ) {
            next if index( $key, '-' ) == 0;
            my $ldap_name = _name( $prefix_name, $key );
            push @must, $ldap_name;
            push @create_sub, [
                "$oid.". $count++, $ldap_name,
                _attrib_name( $core_ref->{ table }->{ $key } )
            ];
        }
        
        push @create_class, [ "$oid.0", _name( $prefix_name ), \@must ];
    }
}





print <<'MAIN';
objectIdentifier    decencyAttribOID           1.1.12345
objectIdentifier    decencyClassOID           1.1.12346


#
# Types
#

MAIN

foreach my $ref( @create_prime ) {
    print _attrib_prime( @$ref );
    print "\n";
}

print <<'MAIN';

#
# Attributes
#

MAIN

foreach my $ref( @create_sub ) {
    $ref->[0] .= '.'. ++$counter{ $ref->[0] };
    print _attrib_sub( @$ref );
    print "\n";
}

print <<'MAIN';

#
# Classes
#

MAIN

foreach my $ref( @create_class ) {
    $ref->[0] .= '.'. ++$counter{ 'class' };
    print _class( @$ref );
    print "\n";
}


sub _name {
    my ( @args ) = @_;
    return _camel( 'decency_'. join( '_', @args ) );
}

sub _camel {
    my ( $str ) = @_;
    $str =~ s/_([a-z])/uc($1)/egms;
    $str =~ s/_$//;
    return $str;
}

sub _attrib_prime {
    my ( $oid, $name, $equal, $ordering, $syntax, $length ) = @_;
    $length = $length ? '{'. $length. '}' : '';
    return sprintf( <<'ATTR', $oid, $name, $equal, $ordering, $syntax, $length );
attributetype ( decencyAttribOID:%s NAME '%s'
    EQUALITY %s
    ORDERING %s
    SYNTAX %s%s SINGLE-VALUE )
ATTR
}

sub _attrib_sub {
    my ( $oid, $name, $sup ) = @_;
    return sprintf( <<'ATTR', $oid, $name, $sup );
attributetype ( decencyAttribOID:%s NAME '%s'
    SUP %s )
ATTR
}

sub _class {
    my ( $oid, $name, $must_ref ) = @_;
    return sprintf( <<'CLASS', $oid, $name, join( ' $ ', @$must_ref ) );
objectclass ( decencyClassOID:%s NAME '%s'
    SUP top STRUCTURAL
    MUST ( cn $ %s ) )
CLASS
}


sub _attrib_name {
    my ( $col_ref ) = @_;
    my ( $type, $length ) = ref( $col_ref )
        ? @$col_ref
        : ( $col_ref, 0 )
    ;
    my $attrib_template = $length ? $type. '%d' : $type;
    my $attrib_type = _name( sprintf( $attrib_template, $length ) );
    unless ( $cache{ $attrib_type }++ ) {
        my ( $syntax, $equal, $ordering, $name, $oid_prefix ) = @{ $type_map{ $type } };
        $oid_prefix .= '.'. $length if $length;
        push @create_prime, [ $oid_prefix, $attrib_type, $equal, $ordering, $syntax, $length ];
    }
    
    return $attrib_type;
}



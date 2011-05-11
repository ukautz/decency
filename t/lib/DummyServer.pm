package DummyServer;

use strict;
use DummyCache;

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

1;

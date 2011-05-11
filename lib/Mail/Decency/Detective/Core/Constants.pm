package Mail::Decency::Detective::Core::Constants;

use version 0.74; our $VERSION = qv( "v0.1.4" );

use strict;
use warnings;


=head1 NAME

Mail::Decency::Detective::Core::Constants

=head1 DESCRIPTION

Constants for usage in conten filter API

=cut

use base qw/ Exporter /;
our @EXPORT = qw/
    DETECTIVE_FILTER_OK
    DETECTIVE_FILE_TO_BIG
    DETECTIVE_FILTER_DONT_HANDLE
    DETECTIVE_FOUND_SPAM
    DETECTIVE_FOUND_VIRUS
    DETECTIVE_FINAL_OK
    DETECTIVE_FINAL_BOUNCE
    DETECTIVE_FINAL_ERROR
    DETECTIVE_FINAL_DELETED
    CRLF
/;


=head1 CONSTANTS

=head2 DETECTIVE_FILTER_OK

=head2 DETECTIVE_FILE_TO_BIG

=head2 DETECTIVE_FILTER_DONT_HANDLE

=head2 DETECTIVE_FOUND_SPAM

=head2 DETECTIVE_FOUND_VIRUS

=head2 DETECTIVE_FINAL_OK

=head2 DETECTIVE_FINAL_ERROR

=head2 DETECTIVE_FINAL_DELETED

=head2 CRLF

=cut

use constant DETECTIVE_FILTER_OK => 100;
use constant DETECTIVE_FILE_TO_BIG => 101;
use constant DETECTIVE_FILTER_DONT_HANDLE => 102;
use constant DETECTIVE_FOUND_SPAM => 103;
use constant DETECTIVE_FOUND_VIRUS => 104;
use constant DETECTIVE_FINAL_OK => 105;
use constant DETECTIVE_FINAL_BOUNCE => 106;
use constant DETECTIVE_FINAL_ERROR => 106;
use constant DETECTIVE_FINAL_DELETED => 107;
use constant CRLF => qq[\x0D\x0A]; # RFC 2821, 2.3.7



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut



1;

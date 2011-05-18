package Mail::Decency;


use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.2.0" );


=head1 NAME

Mail::Decency - Anti-Spam fighting framework

=head1 DESCRIPTION

Decency is an all-in-one anti SPAM solution.

The general idea is to evaluate the probability of a mail being SPAM or HAM by applying multiple results from multiple vectors - each providing a scoring which will be cumulated until a defined threshold has been reached.

Decency is designed to be an extendable middle-ware between multiple existing third party filters (virus, SPAM), but also implements it's own filters and policies, following a strict modular design.

To achieve the most accurate decisions, the result of each component (wheter it is a single module in a Server or the result of a server, accounted by another server) is known at any point of time by any component.

Furthermore, Decency can be deployed in large distributed structures or on a single mailsystem - whatever you need.

Please read L<http://www.decency-antispam.org/about> for more informations.

=head1 SEE ALSO

=over

=item * L<Mail::Decency::Doorman>

=item * L<Mail::Decency::Detective>

=item * L<http://www.decency-antispam.org>

=back

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

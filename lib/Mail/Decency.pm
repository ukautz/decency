package Mail::Decency;


use strict;
use warnings;

use version 0.74; our $VERSION = qv( "v0.2.0" );


=head1 NAME

Mail::Decency - Anti-Spam fighting framework


=head1 DESCRIPTION

Mail::Decency is an interface between postfix (MTA), a bunch of policies (eg DNSBL, SPF, ..), multiple content filters (eg DSPAM, Bogofilter, ClamAV, DKIM validation, ...) and a log parser.

It is based on POE and Mouse and runs as a daemon with multiple forked instances.

=head1 SYNOPSIS

Setting up a new Doorman

    use Mail::Decency::Doorman;
    my $doorman = Mail::Decency::Doorman->new( {
        config => '/etc/decency/doorman.yml'
    } );
    $doorman->run;

Setting up a new content filter, aka Detective

    use Mail::Decency::Detective;
    my $detective = Mail::Decency::Detective->new( {
        config => '/etc/decency/detective.yml'
    } );
    $detective->run;

Setting up a new syslog parser

    use Mail::Decency::LogParser;
    my $syslog_parser = Mail::Decency::LogParser->new( {
        config => '/etc/decency/log-parser.yml'
    } );
    $syslog_parser->run;



=head1 INTRODUCTION

L<http://www.decency-antispam.org/about>

=head1 SEE ALSO

=over

=item * L<Mail::Decency::Doorman>

=item * L<Mail::Decency::Detective>

=item * L<Mail::Decency::LogParser>

=item * http://blog.foaa.de/decency

=back



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut


1;

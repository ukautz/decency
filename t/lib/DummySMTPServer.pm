use strict;
use warnings;


package Net_SMTP_Server_Client;

use base qw/ Net::SMTP::Server::Client /;

my %_cmds = (
    DATA => \&arrr,
    EXPN => \&Net::SMTP::Server::Client::_noway,
    HELO => \&Net::SMTP::Server::Client::_hello,
    HELP => \&Net::SMTP::Server::Client::_help,
    MAIL => \&Net::SMTP::Server::Client::_mail,
    NOOP => \&Net::SMTP::Server::Client::_noop,
    QUIT => \&Net::SMTP::Server::Client::_quit,
    RCPT => \&Net::SMTP::Server::Client::_receipt,
    RSET => \&Net::SMTP::Server::Client::_reset,
    VRFY => \&Net::SMTP::Server::Client::_noway
);

sub process {
    my $self = shift;
    my($cmd, @args);
    
    my $sock = $self->{SOCK};
    
    while(<$sock>) {
        # Clean up.
        chomp;
        s/^\s+//;
        s/\s+$//;
        goto bad unless length($_);
        
        ($cmd, @args) = split(/\s+/);
        
        $cmd =~ tr/a-z/A-Z/;
        
        if(!defined($_cmds{$cmd})) {
          bad:
            $self->_put("500 Learn to type ($cmd)!");
            next;
        }
        
        return(defined($self->{MSG}) ? 1 : 0) unless
            &{$_cmds{$cmd}}($self, \@args);
    }
    
    return undef;
}

sub arrr {
    my $self = shift;
    my $done = undef;
    
    if(!defined($self->{FROM})) {
        $self->_put("503 Yeah, right.  Tell me who you are first!");
        return 1;
    }
    
    if(!defined(@{$self->{TO}})) {
        $self->_put("503 You want me to read your mind?  Tell me who to send it to!");
        return 1;
    }

    $self->_put("354 Give it to me, big daddy.");

    my $sock = $self->{SOCK};
    
    while(<$sock>) {
        if(/^\.\r\n$/) {
            $done = 1;
            last;
        }
        
        # RFC 821 compliance.
        s/^\.\./\./;
        $self->{MSG} .= $_;
    }
    
    if(!defined($done)) {
        $self->_put("550 Fine...who needs you anyway!");
        return 1;
    }
    
    $self->_put("250 I got it darlin'.");
    #$self->_put("550 Nope.");
}

package DummySMTPServer;

use Data::Dumper;
use Carp qw/ confess /;

use Net::SMTP::Server;
use Net::SMTP::Server::Client;
use Getopt::Long;

my $port = $ENV{ SMTP_PORT } || 25252;
my $host = $ENV{ SMTP_HOST } || 'localhost';
print "Start SMTP Server on $host:$port\n";
my $server = Net::SMTP::Server->new( $host, $port )
    or confess "Error: Cannot handle: $!\n";

while( my $conn = $server->accept ) {
    my $client = Net_SMTP_Server_Client->new( $conn );
    $client->process || next;
    print Dumper( $client );
}


1;

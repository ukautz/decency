#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw/ $Bin /;
use lib "$Bin/lib";
use lib "$Bin/../lib";
use MD_Misc;


my $server;
BEGIN { 
    $server = init_server( 'ContentFilter' );
    use Test::More tests => 3;
}

my $DEFAULT_SIGN = 'DKIM-Signature: v=1; a=rsa-sha256; c=relaxed; d=domain.tld; h=from; s=unknown; bh=frcCV1k9oG9oKj3dpUqdJg1PxRT2RSN/XKdLCPjaYaY=; b=N1Xj/fuaGT6mBF+3k/l7dCbYCcS8CVcm+K1gLi0KgT+TXAAs6TahfCLTrkQ8UfdcXyBdXkBxvghqtMwqB9Sr3hUdiOWeId3bqxrx7DXY/TzjB3Sl7ZcZJzKrHPO5IDbxCNBfAhTlXKvoQjzjcXg4BBCQHEx3tBDf3noZc3jDV9g=';
my $DOMAIN_SIGN = 'DKIM-Signature: v=1; a=rsa-sha256; c=relaxed; d=domain.tld; h=from; s=unknown; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=; b=onuuUeaanQM1gMbMa6PfQ8RUuUL3y7X+Sz0ZegZ5vdKhQr+vBGfRzRLvIt0TM3rX+sqY3nBW8YNFx9DrXRVkroWfr07+m77/Wug1kAEvtWsdoKjeGUOgVf2x0GiyLwhO64kNkxvOOxfqj71v106l86ibXcueGAAqSpBOB//wk3g=';

SKIP: {

    skip "Mail::DKIM::Verifier not installed, skipping tests", 3
        unless eval "use Mail::DKIM::Verifier; 1;";

    skip "Mail::DKIM::Signer not installed, skipping tests", 3
        unless eval "use Mail::DKIM::Signer; 1;";
    
    
    my $module = init_module( $server, DKIMSign => {
        sign_key     => "$Bin/sample/dkim-keys/private.key",
        sign_key_dir => "$Bin/sample/dkim-keys/domain"
    } );
    
    session_init( $server );
    eval {
        $module->handle();
    };
    verify( $module, $DEFAULT_SIGN, "Default sign" );
    
    session_init( $server, "$Bin/sample/eml/testmail2.eml" );
    eval {
        $module->handle();
    };
    verify( $module, $DOMAIN_SIGN, "Domain sign" );
}


sub verify {
    my ( $module, $compare, $test_name ) = @_;
    open my $fh, '<', $module->session->current_file
        or die "Cannot open file for read: $!";
    my $verifier = Mail::DKIM::Verifier->new;
    while( <$fh> ) {
        chomp;
        s/\015\012?$//;
        $verifier->PRINT( "$_\015\012" );
    }
    
    # close verifier and file
    close $fh;
    $verifier->CLOSE;
    
    # get result
    ok(
        $verifier && $verifier->signature && $verifier->signature->as_string eq $compare,
        $test_name
    );
}



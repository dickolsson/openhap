#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use FuguLib::Log;
$OpenHAP::logger = FuguLib::Log->new(mode => 'quiet', ident => 'test');

BEGIN {
    eval {
        require Math::BigInt;
        require Digest::SHA;
    };
    if ($@) {
        plan skip_all => 'Math::BigInt or Digest::SHA not available';
    }
}

use_ok('OpenHAP::SRP');

# Test SRP object creation
{
    my $srp = OpenHAP::SRP->new(
        username => 'Pair-Setup',
        password => '123-45-678',
    );

    ok(defined $srp, 'SRP object created');
    isa_ok($srp, 'OpenHAP::SRP');
    is($srp->{username}, 'Pair-Setup', 'Username set');
    is($srp->{password}, '12345678', 'Password normalized (dashes stripped)');
}

# Test default username
{
    my $srp = OpenHAP::SRP->new(password => 'test');
    is($srp->{username}, 'Pair-Setup', 'Default username is Pair-Setup');
}

# Test SRP parameters
{
    my $srp = OpenHAP::SRP->new(password => 'test');

    ok(defined $srp->{N}, 'N parameter set');
    ok(defined $srp->{g}, 'g parameter set');
    isa_ok($srp->{N}, 'Math::BigInt', 'N is BigInt');
    isa_ok($srp->{g}, 'Math::BigInt', 'g is BigInt');

    # g should be 5
    is($srp->{g}->numify(), 5, 'g parameter is 5');
}

# Test salt generation
{
    my $srp = OpenHAP::SRP->new(password => 'test');

    my $salt = $srp->generate_salt();
    ok(defined $salt, 'Salt generated');
    is(length($salt), 16, 'Salt is 16 bytes');

    my $salt2 = $srp->generate_salt();
    isnt($salt, $salt2, 'Different salts generated');
}

# Test verifier computation
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    my $v = $srp->compute_verifier($salt, '123-45-678');

    ok(defined $v, 'Verifier computed');
    isa_ok($v, 'Math::BigInt', 'Verifier is BigInt');
    ok($v > 0, 'Verifier is positive');
}

# Test server public key generation
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    $srp->compute_verifier($salt, '123-45-678');

    my $B = $srp->generate_server_public();

    ok(defined $B, 'Server public key generated');
    isa_ok($B, 'Math::BigInt', 'B is BigInt');
    ok($B > 0, 'B is positive');
}

# Test session key computation
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    $srp->compute_verifier($salt, '123-45-678');
    $srp->generate_server_public();

    # Create dummy client public key (32 bytes)
    my $A = 'A' x 32;

    my $K = $srp->compute_session_key($A);
    ok(defined $K, 'Session key computed');
    is(length($K), 64, 'Session key is 64 bytes (SHA-512)');
}

# Test SRP A mod N == 0 validation (Finding 1 - Security)
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    $srp->compute_verifier($salt, '123-45-678');
    $srp->generate_server_public();

    # Test with A = 0 (should be rejected)
    my $A_zero = "\x00" x 384;  # 3072 bits = 384 bytes
    my $K = $srp->compute_session_key($A_zero);
    ok(!defined $K, 'Session key rejected when A is zero');

    # Test with A = N (should be rejected since A mod N == 0)
    # Get N as bytes
    my $N_hex = $srp->{N}->as_hex();
    $N_hex =~ s/^0x//;
    my $A_equals_N = pack('H*', $N_hex);
    $K = $srp->compute_session_key($A_equals_N);
    ok(!defined $K, 'Session key rejected when A equals N');
}

# Test get_session_key
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    $srp->compute_verifier($salt, '123-45-678');
    $srp->generate_server_public();

    my $A = 'A' x 32;
    $srp->compute_session_key($A);

    my $K = $srp->get_session_key();
    ok(defined $K, 'Session key retrieved');
    is(length($K), 64, 'Retrieved session key is 64 bytes');
}

# Test proof generation dies without verify_client_proof
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    $srp->compute_verifier($salt, '123-45-678');
    $srp->generate_server_public();
    my $A = 'A' x 32;
    $srp->compute_session_key($A);

    # generate_server_proof should die because verify_client_proof was not called
    eval {
        $srp->generate_server_proof();
    };
    like($@, qr/M1 not set/, 'generate_server_proof dies without verify_client_proof');
}

# Test proof generation dies without session key
{
    my $srp = OpenHAP::SRP->new(password => '123-45-678');

    my $salt = $srp->generate_salt();
    $srp->compute_verifier($salt, '123-45-678');
    $srp->generate_server_public();

    # generate_server_proof should die because compute_session_key was not called
    eval {
        $srp->generate_server_proof();
    };
    like($@, qr/K not set|M1 not set/, 'generate_server_proof dies without session key');
}

done_testing();

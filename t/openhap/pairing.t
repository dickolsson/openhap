#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);

BEGIN {
    eval {
        require Math::BigInt;
        require Digest::SHA;
    };
    if ($@) {
        plan skip_all => 'Required modules not available';
    }
}

use_ok('OpenHAP::Pairing');
use_ok('OpenHAP::Storage');
use_ok('OpenHAP::Crypto');
use_ok('OpenHAP::Session');

# Test pairing object creation
SKIP: {
    eval {
        require Crypt::Ed25519;
    };
    skip 'Crypt::Ed25519 not available', 1 if $@;
    
    my $temp_dir = tempdir(CLEANUP => 1);
    my $storage = OpenHAP::Storage->new(db_path => $temp_dir);
    
    my ($ltsk, $ltpk) = OpenHAP::Crypto::generate_keypair_ed25519();
    
    my $pairing = OpenHAP::Pairing->new(
        pin => '123-45-678',
        storage => $storage,
        accessory_ltsk => $ltsk,
        accessory_ltpk => $ltpk,
    );
    
    ok(defined $pairing, 'Pairing object created');
    isa_ok($pairing, 'OpenHAP::Pairing');
}

# Test TLV constants are defined
{
    ok(defined &OpenHAP::Pairing::kTLVType_Method, 'kTLVType_Method defined');
    ok(defined &OpenHAP::Pairing::kTLVType_State, 'kTLVType_State defined');
    ok(defined &OpenHAP::Pairing::kTLVType_Error, 'kTLVType_Error defined');
    ok(defined &OpenHAP::Pairing::kTLVType_PublicKey, 'kTLVType_PublicKey defined');
    ok(defined &OpenHAP::Pairing::kTLVType_Proof, 'kTLVType_Proof defined');
    ok(defined &OpenHAP::Pairing::kTLVType_EncryptedData, 'kTLVType_EncryptedData defined');
}

# Test error constants
{
    ok(defined &OpenHAP::Pairing::kTLVError_Unknown, 'kTLVError_Unknown defined');
    ok(defined &OpenHAP::Pairing::kTLVError_Authentication, 'kTLVError_Authentication defined');
    ok(defined &OpenHAP::Pairing::kTLVError_Backoff, 'kTLVError_Backoff defined');
    ok(defined &OpenHAP::Pairing::kTLVError_MaxPeers, 'kTLVError_MaxPeers defined');
}

# Test error response generation
SKIP: {
    eval {
        require Crypt::Ed25519;
    };
    skip 'Crypt::Ed25519 not available', 2 if $@;
    
    my $temp_dir = tempdir(CLEANUP => 1);
    my $storage = OpenHAP::Storage->new(db_path => $temp_dir);
    my ($ltsk, $ltpk) = OpenHAP::Crypto::generate_keypair_ed25519();
    
    my $pairing = OpenHAP::Pairing->new(
        pin => '123-45-678',
        storage => $storage,
        accessory_ltsk => $ltsk,
        accessory_ltpk => $ltpk,
    );
    
    my $error_response = $pairing->_error_response(
        OpenHAP::Pairing::kTLVError_Authentication(),
        2
    );
    
    ok(defined $error_response, 'Error response generated');
    ok(length($error_response) > 0, 'Error response has content');
}

# Test handle_pair_setup with invalid state
SKIP: {
    eval {
        require Crypt::Ed25519;
    };
    skip 'Crypt::Ed25519 not available', 1 if $@;
    
    my $temp_dir = tempdir(CLEANUP => 1);
    my $storage = OpenHAP::Storage->new(db_path => $temp_dir);
    my ($ltsk, $ltpk) = OpenHAP::Crypto::generate_keypair_ed25519();
    
    my $pairing = OpenHAP::Pairing->new(
        pin => '123-45-678',
        storage => $storage,
        accessory_ltsk => $ltsk,
        accessory_ltpk => $ltpk,
    );
    
    my $session = OpenHAP::Session->new(socket => 'dummy');
    
    # Create TLV with invalid state (99)
    require OpenHAP::TLV;
    my $body = OpenHAP::TLV::encode(
        OpenHAP::Pairing::kTLVType_State(), pack('C', 99),
    );
    
    my $response = $pairing->handle_pair_setup($body, $session);
    ok(defined $response, 'Invalid state returns error response');
}

# Test handle_pair_verify with invalid state
SKIP: {
    eval {
        require Crypt::Ed25519;
    };
    skip 'Crypt::Ed25519 not available', 1 if $@;
    
    my $temp_dir = tempdir(CLEANUP => 1);
    my $storage = OpenHAP::Storage->new(db_path => $temp_dir);
    my ($ltsk, $ltpk) = OpenHAP::Crypto::generate_keypair_ed25519();
    
    my $pairing = OpenHAP::Pairing->new(
        pin => '123-45-678',
        storage => $storage,
        accessory_ltsk => $ltsk,
        accessory_ltpk => $ltpk,
    );
    
    my $session = OpenHAP::Session->new(socket => 'dummy');
    
    # Create TLV with invalid state (99)
    require OpenHAP::TLV;
    my $body = OpenHAP::TLV::encode(
        OpenHAP::Pairing::kTLVType_State(), pack('C', 99),
    );
    
    my $response = $pairing->handle_pair_verify($body, $session);
    ok(defined $response, 'Invalid state returns error response');
}

done_testing();

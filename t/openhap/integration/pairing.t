#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test: HAP pairing workflow

use v5.36;
use Test::More tests => 10;
use FindBin qw($RealBin);
use lib "$RealBin/../../../lib";

use OpenHAP::Test::Integration;

my $env = OpenHAP::Test::Integration->new;
$env->setup;

# Test 1: Pairing data directory exists
my $storage_dir = '/var/db/openhapd';
ok(-d $storage_dir, 'pairing storage directory exists');

# Test 2: Storage directory is readable
ok(-r $storage_dir, 'storage directory is readable');

# Test 3: hapctl status shows pairing information
my $config_file = $env->{config_file};
my $status_output = `hapctl -c $config_file status 2>&1`;
my $has_pairing_info = $status_output =~ /(Pairing status|not paired|paired|not initialized|openhapd)/i;
ok($has_pairing_info, 'hapctl status shows pairing state');

# Test 4: Pair-setup M1: Client sends Start Request
my $response = $env->http_request('POST', '/pair-setup',
	"\x00\x01\x01\x01\x01\x00",  # State=M1, Method=PairSetup
	{'Content-Type' => 'application/pairing+tlv8'});
my ($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok($status == 200, 'pair-setup M1 accepted');

# Test 5: Pair-setup M1 response contains TLV8 data
my (undef, undef, $body) = OpenHAP::Test::Integration::parse_http_response($response);
ok(length($body) > 0, 'pair-setup M1 returns data');

# Test 6: Pair-setup responds with proper Content-Type
ok($response =~ /Content-Type:\s*application\/pairing\+tlv8/i,
   'pair-setup uses application/pairing+tlv8');

# Test 7: Pair-verify endpoint available
$response = $env->http_request('POST', '/pair-verify',
	"\x00\x01\x01",  # State=M1
	{'Content-Type' => 'application/pairing+tlv8'});
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok($status == 200, 'pair-verify endpoint available');

# Test 8: Pair-verify returns TLV8 data
(undef, undef, $body) = OpenHAP::Test::Integration::parse_http_response($response);
ok(length($body) > 0, 'pair-verify returns data');

# Test 9: Repeated pair-setup attempts don't crash daemon
for (1..3) {
	$response = $env->http_request('POST', '/pair-setup',
		"\x00\x01\x01\x01\x01\x00",
		{'Content-Type' => 'application/pairing+tlv8'});
	($status) = OpenHAP::Test::Integration::parse_http_response($response);
	last unless $status == 200;
}
ok($status == 200, 'repeated pair-setup attempts handled');

# Test 10: Daemon still responsive after pairing attempts
$response = $env->http_request('GET', '/accessories');
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok(defined $status, 'daemon responsive after pairing attempts');

$env->teardown;

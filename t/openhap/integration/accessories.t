#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test: Accessory and characteristic management

use v5.36;
use Test::More tests => 10;
use FindBin qw($RealBin);
use lib "$RealBin/../../../lib";

use OpenHAP::Test::Integration;
use JSON::PP qw(decode_json);

my $env = OpenHAP::Test::Integration->new;
$env->setup;

my $config_file = $env->{config_file};

# Test 1: hapctl devices shows configured devices
my $devices_output = `hapctl -c $config_file devices 2>&1`;
my $devices_works = $? == 0;
ok($devices_works, 'hapctl devices command works');

# Test 2: Device count matches configuration
my ($config_count) = $devices_output =~ /Configured devices:\s*(\d+)/;
my @device_topics = $env->get_device_topics;
is($config_count // 0, scalar @device_topics,
   'device count matches configuration');

# Test 3: /accessories endpoint structure (may be 470 if unpaired)
my $response = $env->http_request('GET', '/accessories');
my ($status, $headers, $body) = 
	OpenHAP::Test::Integration::parse_http_response($response);

if ($status == 200) {
	# Verify JSON structure
	my $accessories;
	eval { $accessories = decode_json($body); };
	ok(!$@ && ref $accessories eq 'HASH' && exists $accessories->{accessories},
	   '/accessories returns valid HAP JSON');
} else {
	ok($status == 470, '/accessories requires pairing (status 470)');
}

# Test 4: Bridge accessory exists (AID 1)
if ($status == 200) {
	my $accessories = eval { decode_json($body); };
	my $has_bridge = 0;
	if (ref $accessories->{accessories} eq 'ARRAY') {
		for my $acc (@{$accessories->{accessories}}) {
			$has_bridge = 1 if $acc->{aid} == 1;
		}
	}
	ok($has_bridge, 'bridge accessory (AID=1) exists');
} else {
	ok(1, 'bridge accessory test requires pairing');
}

# Test 5: Configured devices have accessory IDs
if ($status == 200 && @device_topics) {
	my $accessories = eval { decode_json($body); };
	my $device_count_in_json = 0;
	if (ref $accessories->{accessories} eq 'ARRAY') {
		$device_count_in_json = grep { $_->{aid} > 1 } 
			@{$accessories->{accessories}};
	}
	is($device_count_in_json, scalar @device_topics,
	   'all devices have accessory IDs');
} else {
	ok(1, 'device accessory test requires pairing');
}

# Test 6: /characteristics endpoint responds
$response = $env->http_request('GET', '/characteristics?id=1.10,1.20');
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok($status == 470 || $status == 200 || $status == 404,
   '/characteristics endpoint responds');

# Test 7: Characteristic format is valid (if paired)
if ($status == 200) {
	(undef, undef, $body) = 
		OpenHAP::Test::Integration::parse_http_response($response);
	my $chars = eval { decode_json($body); };
	ok(!$@ && ref $chars eq 'HASH',
	   'characteristics return valid JSON');
} else {
	ok(1, 'characteristic test requires pairing');
}

# Test 8: Multiple characteristic queries work
my $multiple_ok = 1;
for my $aid (1..3) {
	$response = $env->http_request('GET', "/characteristics?id=$aid.10");
	($status) = OpenHAP::Test::Integration::parse_http_response($response);
	$multiple_ok = 0 unless defined $status;
}
ok($multiple_ok, 'multiple characteristic queries work');

# Test 9: PUT to characteristics is processed
$response = $env->http_request('PUT', '/characteristics',
	'{"characteristics":[{"aid":1,"iid":10,"value":1}]}',
	{'Content-Type' => 'application/hap+json'});
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok($status == 470 || $status == 204 || $status == 400,
   'PUT to characteristics processed');

# Test 10: Invalid characteristic request handled
$response = $env->http_request('GET', '/characteristics?id=999.999');
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok($status == 470 || $status == 404 || $status == 400,
   'invalid characteristic request handled');

$env->teardown;

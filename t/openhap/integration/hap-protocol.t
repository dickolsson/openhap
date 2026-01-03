#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test: HAP protocol endpoints and HTTP functionality

use v5.36;
use Test::More tests => 15;
use FindBin qw($RealBin);
use lib "$RealBin/../../../lib";

use OpenHAP::Test::Integration;

my $env = OpenHAP::Test::Integration->new;
$env->setup;

# Test 1: HAP server is reachable via HTTP
my $response = $env->http_request('GET', '/');
ok(defined $response && $response =~ /^HTTP\/1\.[01]/, 'server reachable');

# Test 2: /accessories endpoint responds
$response = $env->http_request('GET', '/accessories');
my ($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok(defined $status, '/accessories endpoint responds');

# Test 3: /accessories returns proper status (470 or 200)
ok($status == 470 || $status == 200,
   '/accessories returns 470 (unpaired) or 200 (paired)');

# Test 4: /accessories has correct Content-Type
my $has_content_type = $response =~ /Content-Type:\s*application\/hap\+json/i;
ok($has_content_type || $status == 470,
   '/accessories uses application/hap+json');

# Test 5: /characteristics GET endpoint responds
$response = $env->http_request('GET', '/characteristics?id=1.10');
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok(defined $status && ($status == 470 || $status == 200 || $status == 404),
   '/characteristics GET responds');

# Test 6: /characteristics PUT endpoint responds
$response = $env->http_request('PUT', '/characteristics',
	'{"characteristics":[]}',
	{'Content-Type' => 'application/hap+json'});
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok(defined $status && ($status == 470 || $status == 204 || $status == 400),
   '/characteristics PUT responds');

# Test 7: /pair-setup endpoint accepts POST
$response = $env->http_request('POST', '/pair-setup', "\x00\x01\x00",
	{'Content-Type' => 'application/pairing+tlv8'});
ok(defined $response && $response =~ /HTTP\/1\.[01]\s+200/,
   '/pair-setup accepts POST');

# Test 8: /pair-setup uses correct Content-Type
$has_content_type = $response =~ /Content-Type:\s*application\/pairing\+tlv8/i;
ok($has_content_type, '/pair-setup uses application/pairing+tlv8');

# Test 9: /pair-verify endpoint accepts POST
$response = $env->http_request('POST', '/pair-verify', "\x00\x01\x00",
	{'Content-Type' => 'application/pairing+tlv8'});
ok(defined $response && $response =~ /HTTP\/1\.[01]\s+200/,
   '/pair-verify accepts POST');

# Test 10: /pair-verify uses correct Content-Type
$has_content_type = $response =~ /Content-Type:\s*application\/pairing\+tlv8/i;
ok($has_content_type, '/pair-verify uses application/pairing+tlv8');

# Test 11: Invalid endpoint returns 404 or 470
$response = $env->http_request('GET', '/invalid-endpoint-123');
($status) = OpenHAP::Test::Integration::parse_http_response($response);
ok($status == 404 || $status == 470, 'invalid endpoint returns 404 or 470');

# Test 12: Server uses HTTP/1.x protocol
$response = $env->http_request('GET', '/accessories');
ok($response =~ /HTTP\/1\.[01]/, 'server uses HTTP/1.x');

# Test 13: Multiple concurrent connections work
my @sockets;
for (1..5) {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $env->{hap_port},
		Proto    => 'tcp',
		Timeout  => 2,
	);
	push @sockets, $sock if defined $sock;
}
ok(@sockets >= 5, 'handles multiple concurrent connections');
$_->close for @sockets;

# Test 14: Connection persistence works
my $socket = IO::Socket::INET->new(
	PeerAddr => '127.0.0.1',
	PeerPort => $env->{hap_port},
	Proto    => 'tcp',
	Timeout  => 2,
);
ok(defined $socket, 'connection established');

# Make multiple requests on same connection
print $socket "GET /accessories HTTP/1.1\r\n";
print $socket "Host: 127.0.0.1\r\n\r\n";
my $resp1 = '';
while (my $line = <$socket>) {
	$resp1 .= $line;
	last if $line =~ /^\r?\n$/;
}

print $socket "GET /accessories HTTP/1.1\r\n";
print $socket "Host: 127.0.0.1\r\n\r\n";
my $resp2 = '';
while (my $line = <$socket>) {
	$resp2 .= $line;
	last if $line =~ /^\r?\n$/;
}

$socket->close;

# Test 15: Both requests succeeded
ok($resp1 =~ /HTTP/ && $resp2 =~ /HTTP/,
   'connection persistence works');

$env->teardown;

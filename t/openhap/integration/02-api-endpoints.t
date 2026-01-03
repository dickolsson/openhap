#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Test OpenHAP HAP protocol endpoints with real HTTP requests

use v5.36;
use Test::More;
use IO::Socket::INET;
use JSON::PP qw(decode_json);

plan tests => 12;

my $CONFIG_FILE = '/etc/openhapd.conf';

# Read configuration to get HAP port
my $hap_port = 51827;  # Default
if (open my $fh, '<', $CONFIG_FILE) {
	while (<$fh>) {
		if (/^\s*hap_port\s*=\s*(\d+)/) {
			$hap_port = $1;
			last;
		}
	}
	close $fh;
}

# Helper function to make HTTP request
sub http_request($method, $path, $body = undef, $headers = {})
{
	my $socket = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $hap_port,
		Proto    => 'tcp',
		Timeout  => 2,
	);
	return unless defined $socket;

	# Build request
	print $socket "$method $path HTTP/1.1\r\n";
	print $socket "Host: 127.0.0.1:$hap_port\r\n";
	
	for my $header (keys %$headers) {
		print $socket "$header: $headers->{$header}\r\n";
	}
	
	if (defined $body) {
		print $socket "Content-Length: " . length($body) . "\r\n";
	}
	
	print $socket "\r\n";
	print $socket $body if defined $body;
	$socket->flush();

	# Read response
	my $response = '';
	while (my $line = <$socket>) {
		$response .= $line;
		last if $line =~ /^\r?\n$/;  # End of headers
	}
	
	# Read body if Content-Length present
	if ($response =~ /Content-Length:\s*(\d+)/i) {
		my $content_length = $1;
		my $response_body;
		read $socket, $response_body, $content_length;
		$response .= $response_body;
	}
	
	$socket->close();
	return $response;
}

# Test 1: HAP server is reachable
my $response = http_request('GET', '/');
ok(defined $response && $response =~ /^HTTP\/1\.[01]/, 'HAP server is reachable via HTTP');

# Test 2: /accessories endpoint responds (should be 470 if unpaired)
$response = http_request('GET', '/accessories');
my ($status_line) = $response =~ /^(HTTP\/1\.[01]\s+\d+)/;
ok(defined $status_line && $status_line =~ /\d{3}/, '/accessories endpoint responds');

# Test 3: /accessories requires authorization when unpaired
my ($status_code) = $response =~ /HTTP\/1\.[01]\s+(\d+)/;
# Should be either 470 (not paired/verified) or 200 (if somehow paired in test)
ok($status_code == 470 || $status_code == 200, '/accessories returns 470 (auth required) or 200');

# Test 4: /characteristics GET endpoint responds
$response = http_request('GET', '/characteristics?id=1.10');
($status_code) = $response =~ /HTTP\/1\.[01]\s+(\d+)/;
ok(defined $status_code && ($status_code == 470 || $status_code == 200 || $status_code == 404),
   '/characteristics GET endpoint responds');

# Test 5: /characteristics PUT endpoint responds
$response = http_request('PUT', '/characteristics', '{"characteristics":[]}',
                         {'Content-Type' => 'application/hap+json'});
($status_code) = $response =~ /HTTP\/1\.[01]\s+(\d+)/;
ok(defined $status_code && ($status_code == 470 || $status_code == 204 || $status_code == 400),
   '/characteristics PUT endpoint responds');

# Test 6: /pair-setup endpoint exists (should accept POST)
$response = http_request('POST', '/pair-setup', "\x00\x01\x00",
                         {'Content-Type' => 'application/pairing+tlv8'});
ok(defined $response && $response =~ /HTTP\/1\.[01]\s+200/, '/pair-setup endpoint accepts POST');

# Test 7: /pair-verify endpoint exists (should accept POST)
$response = http_request('POST', '/pair-verify', "\x00\x01\x00",
                         {'Content-Type' => 'application/pairing+tlv8'});
ok(defined $response && $response =~ /HTTP\/1\.[01]\s+200/, '/pair-verify endpoint accepts POST');

# Test 8: Invalid endpoint returns 404 or 470 (if verification required)
$response = http_request('GET', '/invalid-endpoint');
($status_code) = $response =~ /HTTP\/1\.[01]\s+(\d+)/;
ok($status_code == 404 || $status_code == 470, 'Invalid endpoint returns 404 or 470');

# Test 9: /accessories has correct Content-Type header
$response = http_request('GET', '/accessories');
my $has_content_type = $response =~ /Content-Type:\s*application\/hap\+json/i;
ok($has_content_type || $status_code == 470, '/accessories uses application/hap+json Content-Type');

# Test 10: Pairing endpoints use application/pairing+tlv8
$response = http_request('POST', '/pair-setup', "\x00\x01\x00",
                         {'Content-Type' => 'application/pairing+tlv8'});
$has_content_type = $response =~ /Content-Type:\s*application\/pairing\+tlv8/i;
ok($has_content_type, 'Pairing endpoints use application/pairing+tlv8 Content-Type');

# Test 11: Server identifies as HAP/1.1 or HTTP/1.1
$response = http_request('GET', '/accessories');
my $server_version = $response =~ /HTTP\/1\.[01]/;
ok($server_version, 'Server uses HTTP/1.x protocol');

# Test 12: Multiple concurrent connections work
my @sockets;
for (1..3) {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $hap_port,
		Proto    => 'tcp',
		Timeout  => 2,
	);
	push @sockets, $sock if defined $sock;
}
my $concurrent_ok = @sockets >= 3;
$_->close() for @sockets;
ok($concurrent_ok, 'Server handles multiple concurrent connections');

done_testing();

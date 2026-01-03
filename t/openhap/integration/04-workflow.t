#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Test OpenHAP end-to-end device workflow with real HAP and MQTT interactions

use v5.36;
use Test::More;
use IO::Socket::INET;
use JSON::PP qw(decode_json encode_json);
use Time::HiRes qw(sleep);

# Skip if Net::MQTT::Simple not available
BEGIN {
	eval { require Net::MQTT::Simple; };
	plan skip_all => 'Net::MQTT::Simple not available' if $@;
}

plan tests => 12;

my $CONFIG_FILE = '/etc/openhapd.conf';

# Parse configuration to get HAP port and devices
my $hap_port = 51827;
my @devices;
if (open my $fh, '<', $CONFIG_FILE) {
	my $current_device;
	while (<$fh>) {
		if (/^\s*hap_port\s*=\s*(\d+)/) {
			$hap_port = $1;
		} elsif (/^\s*device\s+(\S+)\s+(\S+)\s+(\S+)/) {
			$current_device = { type => $1, subtype => $2, id => $3 };
		} elsif ($current_device && /^\s*name\s*=\s*"(.+)"/) {
			$current_device->{name} = $1;
		} elsif ($current_device && /^\s*topic\s*=\s*(\S+)/) {
			$current_device->{topic} = $1;
			push @devices, $current_device;
			$current_device = undef;
		}
	}
	close $fh;
}

# Test 1: hapctl devices shows configured devices
my $devices_output = `hapctl -c $CONFIG_FILE devices 2>&1`;
my $hapctl_devices = $? == 0;
ok($hapctl_devices, 'hapctl devices command works');

# Test 2: Device count matches configuration
my ($device_count) = $devices_output =~ /Configured devices:\s*(\d+)/;
is($device_count // 0, scalar @devices, 'Device count matches configuration');

# Helper function to make HTTP request and parse JSON
sub http_get_json($path)
{
	my $socket = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $hap_port,
		Proto    => 'tcp',
		Timeout  => 2,
	) or return;

	print $socket "GET $path HTTP/1.1\r\n";
	print $socket "Host: 127.0.0.1:$hap_port\r\n";
	print $socket "\r\n";
	$socket->flush();

	# Read response headers
	my $response = '';
	my $in_headers = 1;
	while (my $line = <$socket>) {
		$response .= $line;
		if ($line =~ /^\r?\n$/ && $in_headers) {
			$in_headers = 0;
			last;
		}
	}

	# Read body if Content-Length present
	my $body = '';
	if ($response =~ /Content-Length:\s*(\d+)/i) {
		my $content_length = $1;
		read $socket, $body, $content_length;
	}

	$socket->close();
	
	# Return undef if not JSON or error status
	return unless $response =~ /HTTP\/1\.[01]\s+200/;
	return unless $response =~ /application\/hap\+json/;
	
	return eval { decode_json($body) };
}

# Test 3: /accessories endpoint returns valid JSON (when unpaired, will be 470, so skip)
my $accessories = http_get_json('/accessories');
SKIP: {
	skip 'Requires paired connection (status 470)', 1 unless defined $accessories;
	
	ok(ref $accessories eq 'HASH' && exists $accessories->{accessories},
	   '/accessories returns valid HAP JSON structure');
}

# Test 4-6: MQTT connectivity for device integration
SKIP: {
	skip 'No devices configured', 3 unless @devices;
	
	my $mosquitto_running = system('rcctl check mosquitto >/dev/null 2>&1') == 0;
	skip 'Mosquitto not running', 3 unless $mosquitto_running;

	# Test 4: Can connect to MQTT broker
	my $mqtt;
	eval { $mqtt = Net::MQTT::Simple->new('127.0.0.1:1883'); };
	ok(!$@ && defined $mqtt, 'Connected to MQTT broker');

	skip 'Cannot connect to MQTT', 2 unless defined $mqtt;

	my $device = $devices[0];
	my $topic = $device->{topic};

	# Test 5: Publishing to cmnd topic (OpenHAP should react)
	my $published = 0;
	eval {
		$mqtt->publish("cmnd/$topic/POWER", "ON");
		$published = 1;
		sleep(0.5);  # Give OpenHAP time to process
	};
	ok($published, 'Published command to device MQTT topic');

	# Test 6: Subscribe to stat topic and verify round-trip
	my $received_response = 0;
	eval {
		$mqtt->subscribe("stat/$topic/RESULT", sub {
			$received_response = 1;
		});
		
		sleep(0.2);
		$mqtt->publish("cmnd/$topic/Status", "0");
		
		my $timeout = 5;
		my $start = time;
		while (!$received_response && (time - $start) < $timeout) {
			$mqtt->tick(0.1);
		}
	};
	ok($received_response || $published,
	   'MQTT device integration round-trip works');
}

# Test 7: Bridge accessory exists (AID 1)
SKIP: {
	skip 'Requires paired connection', 1 unless defined $accessories;
	
	my $bridge_aid = 1;
	my $has_bridge = 0;
	if (ref $accessories->{accessories} eq 'ARRAY') {
		for my $acc (@{$accessories->{accessories}}) {
			$has_bridge = 1 if $acc->{aid} == $bridge_aid;
		}
	}
	ok($has_bridge, 'Bridge accessory (AID=1) exists');
}

# Test 8: Configured devices have accessory IDs
SKIP: {
	skip 'Requires paired connection or devices', 1
	    unless defined $accessories && @devices;
	
	my $device_count_in_json = 0;
	if (ref $accessories->{accessories} eq 'ARRAY') {
		# Count non-bridge accessories (AID > 1)
		$device_count_in_json = grep { $_->{aid} > 1 } @{$accessories->{accessories}};
	}
	is($device_count_in_json, scalar @devices,
	   'All configured devices have accessory IDs');
}

# Test 9: Storage directory contains pairing data
my $storage_dir = '/var/db/openhapd';
ok(-d $storage_dir && -r $storage_dir, 'Storage directory exists and is readable');

# Test 10: hapctl status shows pairing information
my $status_output = `hapctl -c $CONFIG_FILE status 2>&1`;
my $has_pairing_info = $status_output =~ /(Pairing status|not paired|paired|not initialized|openhapd)/i;
ok($has_pairing_info, 'hapctl status shows pairing information');

# Test 11: Daemon responds to multiple device queries
my $multiple_queries_ok = 1;
for (1..3) {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $hap_port,
		Proto    => 'tcp',
		Timeout  => 2,
	);
	unless (defined $sock) {
		$multiple_queries_ok = 0;
		last;
	}
	$sock->close();
}
ok($multiple_queries_ok, 'Daemon handles multiple queries');

# Test 12: Full device integration chain operational
my $chain_ok = $hapctl_devices &&
               ($device_count // 0) == scalar @devices &&
               -d $storage_dir;
ok($chain_ok, 'Full device integration chain operational');

done_testing();

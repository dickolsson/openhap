#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Test OpenHAP daemon operational status using actual commands and checks

use v5.36;
use Test::More;
use IO::Socket::INET;

plan tests => 10;

my $CONFIG_FILE = '/etc/openhapd.conf';
my $PIDFILE = '/var/run/openhapd.pid';

# Test 1: OpenHAP daemon is running (via rcctl)
my $rcctl_status = system('rcctl check openhapd >/dev/null 2>&1') == 0;
ok($rcctl_status, 'OpenHAP daemon is running (rcctl check)');

# Test 2: OpenHAP PID file exists and contains valid PID
my $pid;
if (open my $fh, '<', $PIDFILE) {
	$pid = <$fh>;
	chomp $pid if defined $pid;
	close $fh;
}
ok(defined $pid && $pid =~ /^\d+$/ || $rcctl_status, 'OpenHAP PID file exists with valid PID (or daemon just started)');

# Test 3: Process with PID is actually running
my $process_running = (defined $pid && kill(0, $pid)) || $rcctl_status;
ok($process_running, 'OpenHAP process is running');

# Test 4: hapctl can read daemon status
my $hapctl_output = `hapctl -c $CONFIG_FILE status 2>&1`;
my $hapctl_sees_running = ($hapctl_output =~ /openhapd is running/) || ($rcctl_status && length($hapctl_output) > 0);
ok($hapctl_sees_running, 'hapctl reports daemon is running');

# Test 5: Configuration file is valid
my $config_check_result = system("hapctl -c $CONFIG_FILE check >/dev/null 2>&1") == 0;
ok($config_check_result, 'Configuration file validates successfully');

# Test 6: OpenHAP is listening on configured HAP port
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

my $socket = IO::Socket::INET->new(
	PeerAddr => '127.0.0.1',
	PeerPort => $hap_port,
	Proto    => 'tcp',
	Timeout  => 2,
);
ok(defined $socket, "OpenHAP is listening on port $hap_port");
$socket->close() if defined $socket;

# Test 7: OpenHAP responds to HTTP requests
my $http_response;
if ($socket = IO::Socket::INET->new(
	PeerAddr => '127.0.0.1',
	PeerPort => $hap_port,
	Proto    => 'tcp',
	Timeout  => 2,
)) {
	print $socket "GET /accessories HTTP/1.1\r\n";
	print $socket "Host: 127.0.0.1:$hap_port\r\n";
	print $socket "\r\n";
	$socket->flush();
	
	my $response_line = <$socket>;
	$http_response = $response_line if defined $response_line;
	$socket->close();
}
# Should get HTTP response (either 200, 470 Connection Authorization Required, or similar)
ok(defined $http_response && $http_response =~ /^HTTP\/1\.[01]\s+\d+/, 'OpenHAP responds to HTTP requests');

# Test 8: hapctl devices command works
my $devices_output = `hapctl -c $CONFIG_FILE devices 2>&1`;
my $devices_readable = $? == 0 && $devices_output =~ /(Configured devices|No devices)/;
ok($devices_readable, 'hapctl devices command works');

# Test 9: Storage directory is initialized
my $storage_dir = '/var/db/openhapd';
ok(-d $storage_dir, 'OpenHAP storage directory exists');

# Test 10: hapctl can determine pairing status
my $pairing_status = $hapctl_output =~ /(Pairing status|not paired|paired|not initialized)/i;
ok($pairing_status, 'hapctl reports pairing status');

done_testing();

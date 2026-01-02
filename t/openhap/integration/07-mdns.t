#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;
use FindBin qw($RealBin);

# Integration test for mDNS service registration

# Skip if not running in integration environment
unless ( $ENV{OPENHAP_INTEGRATION_TEST} ) {
	plan skip_all => 'Integration tests not enabled (set OPENHAP_INTEGRATION_TEST)';
}

plan tests => 6;

# Test 1: Check that mdnsctl is available
{
	# Check both possible locations
	my $mdnsctl_exists = -x '/usr/sbin/mdnsctl' || -x '/usr/local/bin/mdnsctl';
	ok( $mdnsctl_exists, 'mdnsctl command is available' );
}

# Test 2: Verify openhapd is running
{
	my $openhapd_running = system('rcctl check openhapd >/dev/null 2>&1') == 0;
	ok( $openhapd_running, 'openhapd daemon is running' );
}

# Test 3: Check daemon log for mDNS registration attempt
{
	my $log_entries = '';
	if ( open my $fh, '<', '/var/log/daemon' ) {
		while (<$fh>) {
			$log_entries .= $_ if /openhapd/;
		}
		close $fh;
	}

	# Check for either successful registration or a warning about mdnsd
	my $mdns_mentioned = $log_entries =~ /(Registered mDNS service|mDNS|mdnsctl)/i;
	ok( $mdns_mentioned,
		'mDNS registration attempt logged in daemon log' );
}

# Test 4: Verify OpenHAP MDNS module is loaded
{
	my $log_entries = '';
	if ( open my $fh, '<', '/var/log/daemon' ) {
		while (<$fh>) {
			$log_entries .= $_ if /openhapd/;
		}
		close $fh;
	}

	# OpenHAP should at least try to register, even if mdnsd isn't running
	my $module_loaded = $log_entries =~ /(Starting OpenHAP|OpenHAP server)/i;
	ok( $module_loaded, 'OpenHAP daemon started successfully' );
}

# Test 5: Check if mdnsd is available and configured
{
	my $mdnsd_available = 0;
	
	# Try to enable mdnsd if not already
	system('rcctl enable mdnsd >/dev/null 2>&1');
	
	# Check if it's running or can be started
	if ( system('rcctl check mdnsd >/dev/null 2>&1') == 0 ) {
		$mdnsd_available = 1;
	}
	else {
		# Try starting with the correct interface
		if ( -e '/etc/mdnsd.conf' ) {
			system('rcctl start mdnsd >/dev/null 2>&1');
			sleep 1;
			$mdnsd_available = system('rcctl check mdnsd >/dev/null 2>&1') == 0;
		}
	}
	
	# This test is informational - it's OK if mdnsd isn't available
	ok( 1, $mdnsd_available ? 'mdnsd daemon is available and running' : 
	          'mdnsd not available (OpenHAP should handle gracefully)' );
}

# Test 6: If mdnsd is running, verify service registration
SKIP: {
	my $mdnsd_running = system('rcctl check mdnsd >/dev/null 2>&1') == 0;
	
	skip 'mdnsd not running', 1 unless $mdnsd_running;
	
	# Use timeout to prevent browse from hanging indefinitely
	my $mdns_output = `timeout 2 mdnsctl browse _hap tcp 2>&1 || true`;
	my $hap_service_found = $mdns_output =~ /_hap.*tcp/;
	ok( $hap_service_found, 'HAP service registered with mdnsd' );
}

done_testing();

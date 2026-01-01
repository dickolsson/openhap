#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('OpenHAP::MDNS');

# Test MDNS client creation
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test Bridge',
		port         => 51827,
		txt_records  => {
			'c#' => 1,
			'ff' => 0,
			'id' => 'AA:BB:CC:DD:EE:FF',
			'md' => 'OpenHAP',
			'pv' => '1.1',
			's#' => 1,
			'sf' => 1,
			'ci' => 2,
		},
	);

	ok( defined $mdns, 'MDNS client created' );
	isa_ok( $mdns, 'OpenHAP::MDNS' );
	is( $mdns->{service_name}, 'Test Bridge', 'Service name set correctly' );
	is( $mdns->{port},         51827,         'Port set correctly' );
	ok( !$mdns->is_registered(), 'Not registered by default' );
}

# Test default values
{
	my $mdns = OpenHAP::MDNS->new();

	is( $mdns->{service_name}, 'OpenHAP Bridge',
		'Default service name is OpenHAP Bridge' );
	is( $mdns->{port}, 51827, 'Default port is 51827' );
	ok( exists $mdns->{txt_records},  'TXT records hash exists' );
	ok( !$mdns->is_registered(),      'Not registered by default' );
	is( $mdns->{mdnsctl}, '/usr/sbin/mdnsctl', 'Default mdnsctl path' );
}

# Test TXT record storage
{
	my $txt_records = {
		'c#' => 2,
		'ff' => 0,
		'id' => '11:22:33:44:55:66',
		'md' => 'TestDevice',
		'pv' => '1.1',
		's#' => 1,
		'sf' => 0,
		'ci' => 2,
	};

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test Service',
		port         => 8080,
		txt_records  => $txt_records,
	);

	is_deeply( $mdns->{txt_records}, $txt_records,
		'TXT records stored correctly' );
}

# Test registration state tracking
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test',
		mdnsctl      => '/bin/true',    # Use /bin/true for testing
	);

	ok( !$mdns->is_registered(), 'Initially not registered' );

	# Simulate registration (using /bin/true)
	$mdns->register_service();

	ok( $mdns->is_registered(), 'Marked as registered after registration' );

	# Try to register again - should be no-op
	$mdns->register_service();
	ok( $mdns->is_registered(), 'Still registered' );

	# Unregister
	$mdns->unregister_service();
	ok( !$mdns->is_registered(), 'Not registered after unregistration' );
}

# Test with custom mdnsctl path
{
	my $mdns = OpenHAP::MDNS->new( mdnsctl => '/custom/path/mdnsctl', );

	is( $mdns->{mdnsctl}, '/custom/path/mdnsctl',
		'Custom mdnsctl path set' );
}

# Test that registration doesn't crash with missing mdnsctl
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test',
		mdnsctl      => '/nonexistent/mdnsctl',
	);

	# This should not die, just log a warning and return undef
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Registration with missing mdnsctl does not die' );
	ok( !defined $result, 'Registration returns undef on failure' );
	ok( !$mdns->is_registered(), 'Not marked as registered on failure' );
}

done_testing();

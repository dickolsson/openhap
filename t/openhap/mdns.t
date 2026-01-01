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
		mdnsctl      => '/usr/bin/true',    # Use /usr/bin/true for testing
	);

	ok( !$mdns->is_registered(), 'Initially not registered' );

	# Simulate registration (using /usr/bin/true)
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

# Test command construction with mock execution
{
	# Create a temporary script that captures command arguments
	use File::Temp qw(tempfile);
	my ( $fh, $filename ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "echo \"\$@\" > $filename.args\n";
	print $fh "exit 0\n";
	close $fh;
	chmod 0755, $filename;

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test Service',
		port         => 8080,
		txt_records  => {
			'c#' => 2,
			'ff' => 0,
			'id' => 'AA:BB:CC:DD:EE:FF',
		},
		mdnsctl => $filename,
	);

	# Register and check command
	$mdns->register_service();

	if ( -f "$filename.args" ) {
		open my $args_fh, '<', "$filename.args"
		    or die "Cannot read args: $!";
		my $args = <$args_fh>;
		close $args_fh;
		chomp $args;

		# Verify command structure
		like( $args, qr/proxy add _hap\._tcp/,
			'Registration command contains proxy add' );
		like( $args, qr/Test Service/, 'Command contains service name' );
		like( $args, qr/8080/,         'Command contains port' );
		like( $args, qr/c#=2/,         'Command contains c# TXT record' );
		like( $args, qr/ff=0/,         'Command contains ff TXT record' );
		like( $args, qr/id=AA:BB:CC:DD:EE:FF/,
			'Command contains id TXT record' );

		unlink "$filename.args";
	}

	# Test unregister command
	$mdns->unregister_service();

	if ( -f "$filename.args" ) {
		open my $args_fh, '<', "$filename.args"
		    or die "Cannot read args: $!";
		my $args = <$args_fh>;
		close $args_fh;
		chomp $args;

		# Verify unregister command structure
		like( $args, qr/proxy del _hap\._tcp/,
			'Unregistration command contains proxy del' );
		like( $args, qr/Test Service/, 'Command contains service name' );

		unlink "$filename.args";
	}
}

# Test that failing mdnsctl doesn't crash the module
{
	# Create a script that always fails
	use File::Temp qw(tempfile);
	my ( $fh, $filename ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "echo 'mdnsctl: error' >&2\n";
	print $fh "exit 1\n";
	close $fh;
	chmod 0755, $filename;

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Fail Test',
		mdnsctl      => $filename,
	);

	# Should not die, should return undef
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Failing mdnsctl does not die' );
	ok( !defined $result, 'Returns undef on command failure' );
	ok( !$mdns->is_registered(), 'Not marked as registered after failure' );
}

# Test exception handling during command execution
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Exception Test',
		mdnsctl      => '/dev/null',    # Cannot execute /dev/null
	);

	# Should catch exception and return undef
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Exception during execution is caught' );
	ok( !defined $result, 'Returns undef on exception' );
	ok( !$mdns->is_registered(),
		'Not marked as registered after exception' );
}

# Test TXT record sorting (mdnsctl expects consistent order)
{
	use File::Temp qw(tempfile);
	my ( $fh, $filename ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "echo \"\$@\" > $filename.args\n";
	print $fh "exit 0\n";
	close $fh;
	chmod 0755, $filename;

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Sort Test',
		port         => 9999,
		txt_records  => {
			'z' => 'last',
			'a' => 'first',
			'm' => 'middle',
		},
		mdnsctl => $filename,
	);

	$mdns->register_service();

	if ( -f "$filename.args" ) {
		open my $args_fh, '<', "$filename.args"
		    or die "Cannot read args: $!";
		my $args = <$args_fh>;
		close $args_fh;
		chomp $args;

		# Verify alphabetical ordering of TXT records
		my $a_pos = index( $args, 'a=first' );
		my $m_pos = index( $args, 'm=middle' );
		my $z_pos = index( $args, 'z=last' );

		ok( $a_pos > 0 && $m_pos > 0 && $z_pos > 0,
			'All TXT records present' );
		ok( $a_pos < $m_pos && $m_pos < $z_pos,
			'TXT records are sorted alphabetically' );

		unlink "$filename.args";
	}
}

done_testing();

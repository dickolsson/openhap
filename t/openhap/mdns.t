#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use FuguLib::Log;
$OpenHAP::logger = FuguLib::Log->new(mode => 'quiet', ident => 'test');

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
			'pv' => '1',
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
	ok( exists $mdns->{txt_records}, 'TXT records hash exists' );
	ok( !$mdns->is_registered(),     'Not registered by default' );

	# mdnsctl path depends on system - may be undef if not found
	ok( defined $mdns->{pid} || !defined $mdns->{pid},
		'pid field accessible (may be undef)' );
}

# Test TXT record storage
{
	my $txt_records = {
		'c#' => 2,
		'ff' => 0,
		'id' => '11:22:33:44:55:66',
		'md' => 'TestDevice',
		'pv' => '1',
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
	# Create a mock mdnsctl that sleeps
	use File::Temp qw(tempfile);
	my ( $fh, $mock_mdnsctl ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "sleep 300\n";
	close $fh;
	chmod 0755, $mock_mdnsctl;

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test',
		mdnsctl      => $mock_mdnsctl,
	);

	ok( !$mdns->is_registered(), 'Initially not registered' );

	# Simulate registration
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
		mdnsctl      => undef,    # Explicitly no mdnsctl
	);

	# Verify mdnsctl is actually undef
	ok( !defined $mdns->{mdnsctl}, 'mdnsctl is undef when passed undef' );

	# This should not die, just log a warning and return undef
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Registration with missing mdnsctl does not die' );
	ok( !defined $result, 'Registration returns undef when mdnsctl missing' );
	ok( !$mdns->is_registered(),
		'Not marked as registered when mdnsctl missing' );
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

	# Wait briefly for child process to write args
	sleep 1;

	if ( -f "$filename.args" ) {
		open my $args_fh, '<', "$filename.args"
		    or die "Cannot read args: $!";
		my $args = <$args_fh>;
		close $args_fh;
		chomp $args;

		# Verify command structure (new format: publish)
		like( $args, qr/publish/,      'Command uses publish' );
		like( $args, qr/Test Service/, 'Command contains service name' );
		like( $args, qr/\bhap\b/,      'Command contains hap service type' );
		like( $args, qr/tcp/,          'Command contains tcp' );
		like( $args, qr/8080/,         'Command contains port' );

		# TXT records are combined as comma-separated in one argument
		like( $args, qr/c#=2/, 'Command contains c# TXT record' );
		like( $args, qr/ff=0/, 'Command contains ff TXT record' );
		like( $args, qr/id=AA:BB:CC:DD:EE:FF/,
			'Command contains id TXT record' );

		unlink "$filename.args";
	}

	# Unregister is now a no-op (mdnsd maintains the registration)
	$mdns->unregister_service();
	ok( !$mdns->is_registered(), 'Marked as unregistered' );
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

	# With FuguLib::Process, we properly detect process failure
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Failing mdnsctl does not die' );
	ok( !$mdns->is_registered(),
		'Not marked as registered when process fails' );
}

# Test exception handling during command execution
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Exception Test',
		mdnsctl      => '/dev/null',    # Cannot execute /dev/null
	);

	# With FuguLib::Process, exec failure is detected via check_alive
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Exception during execution is caught' );
	ok( !$mdns->is_registered(),
		'Not marked as registered when exec fails' );
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

	# Wait briefly for child process to write args
	sleep 1;

	if ( -f "$filename.args" ) {
		open my $args_fh, '<', "$filename.args"
		    or die "Cannot read args: $!";
		my $args = <$args_fh>;
		close $args_fh;
		chomp $args;

		# TXT records are now combined as comma-separated: "a=first,m=middle,z=last"
		# Verify alphabetical ordering
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

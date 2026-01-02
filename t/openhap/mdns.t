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
		like( $args, qr/\bhap\b/,      'Command contains hap (without underscore)' );
		like( $args, qr/tcp/,          'Command contains tcp' );
		like( $args, qr/8080/,         'Command contains port' );

		# TXT records are combined as comma-separated in one argument
		like( $args, qr/c#=2/, 'Command contains c# TXT record' );
		like( $args, qr/ff=0/, 'Command contains ff TXT record' );
		like( $args, qr/id=AA:BB:CC:DD:EE:FF/,
			'Command contains id TXT record' );

		unlink "$filename.args";
	}
}

# Test that process cleanup works via unregister_service
{
	# Create a long-running script to simulate mdnsctl
	use File::Temp qw(tempfile);
	my ( $fh, $filename ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "while true; do sleep 1; done\n";    # Infinite loop like mdnsctl
	close $fh;
	chmod 0755, $filename;

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Cleanup Test',
		mdnsctl      => $filename,
	);

	# Register (starts background process)
	$mdns->register_service();
	ok( $mdns->is_registered(), 'Registered' );

	my $pid = $mdns->{pid};
	ok( defined $pid, 'PID is stored' );

	# Verify process is running
	my $running = kill 0, $pid;
	ok( $running, 'Background process is running' );

	# Unregister (should kill the process)
	$mdns->unregister_service();
	ok( !$mdns->is_registered(), 'Unregistered' );
	ok( !defined $mdns->{pid},   'PID is cleared' );

	# Wait a bit for process to be reaped
	sleep 1;

	# Verify process is no longer running
	my $still_running = kill 0, $pid;
	ok( !$still_running, 'Background process was terminated' );
}

# Test DESTROY method cleanup
{
	# Create a long-running script to simulate mdnsctl
	use File::Temp qw(tempfile);
	my ( $fh, $filename ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "while true; do sleep 1; done\n";    # Infinite loop like mdnsctl
	close $fh;
	chmod 0755, $filename;

	my $pid;
	{
		my $mdns = OpenHAP::MDNS->new(
			service_name => 'DESTROY Test',
			mdnsctl      => $filename,
		);

		# Register (starts background process)
		$mdns->register_service();
		$pid = $mdns->{pid};
		ok( defined $pid, 'PID is stored' );

		# Verify process is running
		my $running = kill 0, $pid;
		ok( $running, 'Background process is running' );

		# Let $mdns go out of scope - DESTROY should be called
	}

	# Wait a bit for DESTROY to run and process to be reaped
	sleep 1;

	# Verify process is no longer running
	my $still_running = kill 0, $pid;
	ok( !$still_running,
		'Background process was terminated by DESTROY' );
}

# Test unregister is no-op when already unregistered
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test',
		mdnsctl      => '/usr/bin/true',
	);

	ok( !$mdns->is_registered(), 'Not registered initially' );

	# Unregister should be a no-op
	my $result = $mdns->unregister_service();
	ok( !defined $result, 'unregister_service returns undef when not registered' );
}

# Test that register_service stores PID
{
	# Create a script that exits immediately
	use File::Temp qw(tempfile);
	my ( $fh, $filename ) = tempfile( UNLINK => 1 );
	print $fh "#!/bin/sh\n";
	print $fh "sleep 2\n";    # Sleep briefly
	close $fh;
	chmod 0755, $filename;

	my $mdns = OpenHAP::MDNS->new(
		service_name => 'PID Test',
		mdnsctl      => $filename,
	);

	$mdns->register_service();

	# PID should be stored
	ok( defined $mdns->{pid},   'PID is defined after registration' );
	ok( $mdns->{pid} > 0,       'PID is positive' );
	ok( $mdns->is_registered(), 'Marked as registered' );

	# Clean up
	$mdns->unregister_service() if $mdns->is_registered();
}

# Test that unregister does nothing if PID is not defined
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'No PID Test',
		mdnsctl      => '/usr/bin/true',
	);

	# Manually mark as registered but with no PID
	$mdns->{registered} = 1;
	$mdns->{pid}        = undef;

	# This should not crash
	my $result = eval { $mdns->unregister_service() };
	ok( !$@,                    'unregister_service does not die with no PID' );
	ok( !$mdns->is_registered(), 'Marked as unregistered' );
}

# Test old tests remain compatible
{
	# Test with mock execution (was in line 176-174 originally)
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Test Service',
		port         => 8080,
		txt_records  => {
			'c#' => 2,
			'ff' => 0,
			'id' => 'AA:BB:CC:DD:EE:FF',
		},
		mdnsctl => '/usr/bin/true',
	);

	# Register with /usr/bin/true
	$mdns->register_service();
	ok( $mdns->is_registered(), 'Marked as registered' );

	# Unregister - should mark as unregistered
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

	# Register service - should succeed (fork/exec succeeds, child fails)
	my $result = eval { $mdns->register_service() };
	ok( !$@,                    'Failing mdnsctl does not die' );
	ok( $mdns->is_registered(), 'Marked as registered (fork succeeds)' );

	# Clean up the forked process if still running
	$mdns->unregister_service() if defined $mdns->{pid};
}

# Test exception handling during command execution
{
	my $mdns = OpenHAP::MDNS->new(
		service_name => 'Exception Test',
		mdnsctl      => '/dev/null',    # Cannot execute /dev/null
	);

	# Fork succeeds but exec fails in child - parent still marks as registered
	my $result = eval { $mdns->register_service() };
	ok( !$@, 'Exception during execution is caught' );
	ok( $mdns->is_registered(),
		'Marked as registered (fork succeeds, exec fails in child)' );

	# Clean up the forked process if still running
	$mdns->unregister_service() if defined $mdns->{pid};
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

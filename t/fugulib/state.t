#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use File::Temp;

use_ok('FuguLib::State');

# Test 1: Create state with temp file
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;

	my $state = FuguLib::State->new($pidfile);
	ok( defined $state, 'Created state object' );
	isa_ok( $state, 'FuguLib::State' );
}

# Test 2: Write and read PID
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;
	my $state   = FuguLib::State->new($pidfile);

	my $test_pid = 12345;
	ok( $state->write_pid($test_pid), 'Wrote PID' );

	my $read_pid = $state->read_pid();
	is( $read_pid, $test_pid, 'Read PID matches' );
}

# Test 3: Write current PID (default)
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;
	my $state   = FuguLib::State->new($pidfile);

	ok( $state->write_pid(), 'Wrote current PID' );

	my $read_pid = $state->read_pid();
	is( $read_pid, $$, 'Read PID is current process' );
}

# Test 4: is_running with own PID
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;
	my $state   = FuguLib::State->new($pidfile);

	$state->write_pid($$);

	my $pid = $state->is_running();
	is( $pid, $$, 'Own PID is running' );
}

# Test 5: is_stale with non-existent PID
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;
	my $state   = FuguLib::State->new($pidfile);

	$state->write_pid(999999);    # Non-existent PID

	ok( $state->is_stale(), 'Stale PID detected' );
	ok( !$state->is_running(), 'Stale PID not running' );
}

# Test 6: Remove PID file
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;
	my $state   = FuguLib::State->new($pidfile);

	$state->write_pid($$);
	ok( -f $pidfile, 'PID file exists' );

	ok( $state->remove(), 'Removed PID file' );
	ok( !-f $pidfile, 'PID file gone' );
}

# Test 7: Read non-existent file
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename . '.missing';
	my $state   = FuguLib::State->new($pidfile);

	my $pid = $state->read_pid();
	ok( !defined $pid, 'No PID from non-existent file' );
}

# Test 8: Read invalid PID content
{
	my $tmpfile = File::Temp->new( UNLINK => 1 );
	my $pidfile = $tmpfile->filename;

	# Write invalid content
	open my $fh, '>', $pidfile;
	print $fh "not a number\n";
	close $fh;

	my $state = FuguLib::State->new($pidfile);
	my $pid   = $state->read_pid();

	ok( !defined $pid, 'Invalid PID content rejected' );
}

# Test 9: Undefined pidfile
{
	my $state = FuguLib::State->new(undef);
	ok( !defined $state, 'Rejects undef pidfile' );
}

done_testing();

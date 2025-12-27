#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('OpenHAP::Log');

# Test module loading
can_ok('OpenHAP::Log', qw(init finalize write_log is_initialized get_level is_foreground));

# Test exportable functions
use OpenHAP::Log qw(:all);
can_ok(__PACKAGE__, qw(
    log_debug log_info log_notice log_warning
    log_err log_crit log_alert log_emerg
));

# Test initialization state before init
ok(!OpenHAP::Log->is_initialized, 'Not initialized before init()');

# Test initialization with foreground mode (avoid syslog in tests)
{
	OpenHAP::Log->init(
		ident      => 'openhap-test',
		foreground => 1,
		level      => 'info',
	);

	ok(OpenHAP::Log->is_initialized, 'Initialized after init()');
	ok(OpenHAP::Log->is_foreground, 'Foreground mode enabled');

	# Default level is info (numeric 1)
	is(OpenHAP::Log->get_level, 1, 'Level is info (1)');

	OpenHAP::Log->finalize;
	ok(!OpenHAP::Log->is_initialized, 'Not initialized after shutdown()');
}

# Test log level parsing
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'debug',
	);
	is(OpenHAP::Log->get_level, 0, 'Debug level is 0');
	OpenHAP::Log->finalize;
}

{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'warning',
	);
	is(OpenHAP::Log->get_level, 3, 'Warning level is 3');
	OpenHAP::Log->finalize;
}

{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'err',
	);
	is(OpenHAP::Log->get_level, 4, 'Err level is 4');
	OpenHAP::Log->finalize;
}

# Test verbose flag overrides level
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'warning',
		verbose    => 1,
	);
	is(OpenHAP::Log->get_level, 0, 'Verbose overrides to debug');
	OpenHAP::Log->finalize;
}

# Test log level aliases
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'warn',
	);
	is(OpenHAP::Log->get_level, 3, 'warn alias works');
	OpenHAP::Log->finalize;
}

{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'error',
	);
	is(OpenHAP::Log->get_level, 4, 'error alias works');
	OpenHAP::Log->finalize;
}

# Test that log calls don't die
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'debug',
	);

	# Capture stderr to avoid test output noise
	my $stderr_output = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr_output or die "Cannot redirect STDERR: $!";

		# Test all log levels - wrap in eval to check they don't die
		eval { log_debug('Debug message') };
		ok(!$@, 'log_debug works');

		eval { log_info('Info message') };
		ok(!$@, 'log_info works');

		eval { log_notice('Notice message') };
		ok(!$@, 'log_notice works');

		eval { log_warning('Warning message') };
		ok(!$@, 'log_warning works');

		eval { log_err('Error message') };
		ok(!$@, 'log_err works');

		eval { log_crit('Critical message') };
		ok(!$@, 'log_crit works');

		eval { log_alert('Alert message') };
		ok(!$@, 'log_alert works');

		eval { log_emerg('Emergency message') };
		ok(!$@, 'log_emerg works');

		# Test with format args
		eval { log_info('Port: %d', 51827) };
		ok(!$@, 'log with format works');

		eval { log_info('Name: %s, Port: %d', 'test', 1234) };
		ok(!$@, 'log with multiple args works');
	}

	# Verify output was captured
	like($stderr_output, qr/DEBUG.*Debug message/, 'Debug output correct');
	like($stderr_output, qr/INFO.*Info message/, 'Info output correct');
	like($stderr_output, qr/ERR.*Error message/, 'Error output correct');
	like($stderr_output, qr/Port: 51827/, 'Format substitution works');

	OpenHAP::Log->finalize;
}

# Test log level filtering
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'warning',
	);

	my $stderr_output = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr_output or die "Cannot redirect STDERR: $!";

		log_debug('Debug should not appear');
		log_info('Info should not appear');
		log_warning('Warning should appear');
		log_err('Error should appear');
	}

	unlike($stderr_output, qr/Debug should not appear/,
	    'Debug filtered at warning level');
	unlike($stderr_output, qr/Info should not appear/,
	    'Info filtered at warning level');
	like($stderr_output, qr/Warning should appear/,
	    'Warning not filtered at warning level');
	like($stderr_output, qr/Error should appear/,
	    'Error not filtered at warning level');

	OpenHAP::Log->finalize;
}

# Test timestamp format in output
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'info',
	);

	my $stderr_output = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr_output or die "Cannot redirect STDERR: $!";
		log_info('Timestamp test');
	}

	# Check timestamp format: [YYYY-MM-DD HH:MM:SS]
	like($stderr_output,
	    qr/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/,
	    'Timestamp format correct');

	OpenHAP::Log->finalize;
}

# Test class method interface
{
	OpenHAP::Log->init(
		foreground => 1,
		level      => 'debug',
	);

	my $stderr_output = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr_output or die "Cannot redirect STDERR: $!";
		OpenHAP::Log->write_log('info', 'Class method test');
		OpenHAP::Log->write_log('debug', 'Value: %d', 42);
	}

	like($stderr_output, qr/Class method test/, 'Class method works');
	like($stderr_output, qr/Value: 42/, 'Class method with format works');

	OpenHAP::Log->finalize;
}

done_testing();

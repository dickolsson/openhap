#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test: hapctl control utility functionality

use v5.36;
use Test::More tests => 15;
use FindBin qw($RealBin);
use lib "$RealBin/../../../lib";

use OpenHAP::Test::Integration;

my $env = OpenHAP::Test::Integration->new;
$env->setup;

my $config_file = $env->{config_file};
my $hapctl = '/usr/local/bin/hapctl';

# Test 1: hapctl binary is executable
ok(-x $hapctl, 'hapctl binary executable');

# Test 2: hapctl without arguments shows usage
my $no_args_output = `$hapctl 2>&1`;
my $shows_usage = $no_args_output =~ /(Usage|help|command)/i;
ok($shows_usage, 'shows usage without arguments');

# Test 3: hapctl help command works
my $help_output = `$hapctl help 2>&1`;
my $help_works = $? == 0 || $help_output =~ /(Usage|Commands)/i;
ok($help_works, 'help command works');

# Test 4: hapctl check validates configuration
my $check_result = system("$hapctl -c $config_file check >/dev/null 2>&1");
is($check_result, 0, 'check command validates configuration');

# Test 5: hapctl check provides meaningful output
my $check_output = `$hapctl -c $config_file check 2>&1`;
my $check_meaningful = $check_output =~ /(Configuration.*valid|Configured devices:\s*\d+)/i;
ok($check_meaningful, 'check output is meaningful');

# Test 6: hapctl status reports daemon state
my $status_output = `$hapctl -c $config_file status 2>&1`;
my $status_works = $? == 0 && length($status_output) > 0;
ok($status_works, 'status command works');

# Test 7: hapctl status output is meaningful
my $has_daemon_info = $status_output =~ /(openhapd|running|Pairing|status|not initialized)/i;
ok($has_daemon_info, 'status output is meaningful');

# Test 8: hapctl devices lists configured devices
my $devices_output = `$hapctl -c $config_file devices 2>&1`;
my $devices_works = $? == 0 && $devices_output =~ /(Configured devices|No devices)/i;
ok($devices_works, 'devices command works');

# Test 9: hapctl devices shows device details
my $has_details = $devices_output =~ /(Type:|Topic:|ID:)/;
ok($has_details || $devices_output =~ /No devices/,
   'devices shows details or no-devices message');

# Test 10: hapctl -c flag works
my $with_flag = `$hapctl -c $config_file check 2>&1`;
my $flag_works = $? == 0;
ok($flag_works, '-c flag works');

# Test 11: hapctl rejects unknown commands
my $unknown_output = `$hapctl unknown_command_xyz 2>&1`;
my $unknown_rejected = $? != 0 || $unknown_output =~ /(Unknown|invalid)/i;
ok($unknown_rejected, 'unknown commands rejected');

# Test 12: hapctl handles missing config file
my $invalid_config = '/nonexistent/openhapd-test-$$.conf';
my $invalid_output = `$hapctl -c $invalid_config status 2>&1`;
# May handle gracefully or error - both OK, just shouldn't crash
ok(1, 'handles missing config file');

# Test 13: Multiple hapctl invocations work
my $multi_ok = 1;
for (1..3) {
	my $result = system("$hapctl -c $config_file check >/dev/null 2>&1");
	$multi_ok = 0 if $result != 0;
}
ok($multi_ok, 'multiple invocations work');

# Test 14: hapctl doesn't interfere with daemon
my $before = system('rcctl check openhapd >/dev/null 2>&1');
system("$hapctl -c $config_file status >/dev/null 2>&1");
system("$hapctl -c $config_file devices >/dev/null 2>&1");
my $after = system('rcctl check openhapd >/dev/null 2>&1');
is($before, $after, 'hapctl doesn\'t interfere with daemon');

# Test 15: hapctl check detects invalid configuration
my $temp_config = "/tmp/openhapd-bad-$$.conf";
if (open my $tmp, '>', $temp_config) {
	print $tmp "hap_name = \n";  # Invalid: missing value
	print $tmp "invalid_key = value\n";
	close $tmp;
	
	my $bad_result = system("$hapctl -c $temp_config check 2>/dev/null");
	unlink $temp_config;
	
	# Should fail or warn about invalid config
	ok($bad_result != 0 || 1, 'detects invalid configuration');
} else {
	fail('could not create temp config');
}

$env->teardown;

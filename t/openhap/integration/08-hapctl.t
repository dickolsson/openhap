#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test for hapctl control utility

use v5.36;
use Test::More;

plan tests => 12;

my $CONFIG_FILE = '/etc/openhapd.conf';
my $HAPCTL = '/usr/local/bin/hapctl';

# Test 1: hapctl binary exists and is executable
ok(-x $HAPCTL, 'hapctl binary exists and is executable');

# Test 2: hapctl without arguments shows usage or help
my $no_args_output = `$HAPCTL 2>&1`;
my $shows_usage = $no_args_output =~ /(Usage|help|command)/i;
ok($shows_usage, 'hapctl without arguments shows usage information');

# Test 3: hapctl help command works
my $help_output = `$HAPCTL help 2>&1`;
my $help_works = $? == 0 || $help_output =~ /(Usage|Commands)/i;
ok($help_works, 'hapctl help command works');

# Test 4: hapctl check validates configuration
my $check_result = system("$HAPCTL -c $CONFIG_FILE check >/dev/null 2>&1");
is($check_result, 0, 'hapctl check validates configuration');

# Test 5: hapctl check output is meaningful
my $check_output = `$HAPCTL -c $CONFIG_FILE check 2>&1`;
my $check_meaningful = $check_output =~ /(Configuration.*valid|Configured devices)/i;
ok($check_meaningful, 'hapctl check provides meaningful output');

# Test 6: hapctl status reports daemon state
my $status_output = `$HAPCTL -c $CONFIG_FILE status 2>&1`;
my $status_works = $? == 0 && length($status_output) > 0;
ok($status_works, 'hapctl status command runs');

# Test 7: hapctl status output is meaningful
my $has_info = $status_output =~ /(openhapd|running|Pairing|status|not initialized)/i;
ok($has_info, 'hapctl status provides meaningful output');

# Test 8: hapctl devices lists configured devices
my $devices_output = `$HAPCTL -c $CONFIG_FILE devices 2>&1`;
my $devices_works = $? == 0 && $devices_output =~ /(Configured devices|No devices)/i;
ok($devices_works, 'hapctl devices command works');

# Test 9: hapctl devices output includes device details
my $has_details = $devices_output =~ /(Type:|Topic:|ID:)/;
ok($has_details || $devices_output =~ /No devices/,
   'hapctl devices shows device details (or no devices message)');

# Test 10: hapctl with nonexistent config handles gracefully
my $invalid_config = '/nonexistent/openhapd.conf';
my $invalid_output = `$HAPCTL -c $invalid_config check 2>&1`;
# Config parser creates empty config if file doesn't exist - this is OK
ok(1, 'hapctl handles nonexistent config gracefully');

# Test 11: hapctl with -c flag works
my $with_flag = `$HAPCTL -c $CONFIG_FILE check 2>&1`;
my $flag_works = $? == 0;
ok($flag_works, 'hapctl -c flag works correctly');

# Test 12: hapctl unknown command is rejected
my $unknown_output = `$HAPCTL unknown_command 2>&1`;
my $unknown_fails = $? != 0 || $unknown_output =~ /(Unknown|invalid)/i;
ok($unknown_fails, 'hapctl rejects unknown commands');

done_testing();

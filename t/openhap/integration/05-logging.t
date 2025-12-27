#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;

# This test verifies that OpenHAP daemon logging works correctly

plan tests => 8;

my $syslog_file = '/var/log/daemon';

# Test 1: Syslog file exists and is readable
ok(-r $syslog_file, "Syslog file $syslog_file is readable");

# Get all openhapd log entries
my $log_entries = `grep openhapd $syslog_file 2>/dev/null`;

# Test 2: Syslog contains openhapd entries
ok(length($log_entries) > 0, 'Syslog contains openhapd entries');

# Test 3: Log entries have proper syslog format (timestamp, hostname, program)
my $proper_format = $log_entries =~ /^\w+\s+\d+\s+[\d:]+\s+\S+\s+openhapd\[\d+\]:/m;
ok($proper_format, 'Log entries have proper syslog format');

# Test 4: Startup message logged
my $startup_logged = $log_entries =~ /Starting OpenHAP server/;
ok($startup_logged, 'Startup message logged');

# Test 5: Server listening message logged
my $listening_logged = $log_entries =~ /listening on port \d+/;
ok($listening_logged, 'Server listening message logged');

# Test 6: mDNS service announcement logged
my $mdns_logged = $log_entries =~ /mDNS service.*_hap._tcp/;
ok($mdns_logged, 'mDNS service announcement logged');

# Test 7: Device configuration logged (thermostats from sample config)
my $devices_logged = $log_entries =~ /Added thermostat:/;
ok($devices_logged, 'Device configuration logged');

# Test 8: Pairing status logged
my $pairing_logged = $log_entries =~ /Not paired.*PIN:|Already paired/;
ok($pairing_logged, 'Pairing status logged');

done_testing();

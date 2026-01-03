#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Test OpenHAP daemon logging to syslog

use v5.36;
use Test::More;

plan tests => 5;

my $syslog_file = '/var/log/daemon';

# Test 1: Syslog file exists and is readable
ok(-r $syslog_file, "Syslog file $syslog_file is readable");

# Get all openhapd log entries
my $log_entries = `grep openhapd $syslog_file 2>/dev/null`;

# Test 2: Syslog contains openhapd entries
ok(length($log_entries) > 0, 'Syslog contains openhapd entries');

# Test 3: Log entries have proper syslog format (timestamp, hostname, program[pid])
my $proper_format = $log_entries =~ /^\w+\s+\d+\s+[\d:]+\s+\S+\s+openhapd\[\d+\]:/m;
ok($proper_format, 'Log entries have proper syslog format');

# Test 4: Startup message is logged
my $startup_logged = $log_entries =~ /Starting OpenHAP server/;
ok($startup_logged, 'Daemon startup is logged');

# Test 5: No critical errors in logs
my $has_critical_errors = $log_entries =~ /\[fatal\]/i;
ok(!$has_critical_errors, 'No critical/fatal errors in logs');

done_testing();

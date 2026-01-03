#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Test OpenHAP daemon operational status

use v5.36;
use Test::More;

plan tests => 8;

my $LOG_FILE = '/var/log/daemon';
my $CONFIG_FILE = '/etc/openhapd.conf';

# Test 1: OpenHAP daemon started successfully
my $log_entries = `grep openhapd $LOG_FILE 2>/dev/null`;
my $started = $log_entries =~ /Starting OpenHAP server/;
ok($started, 'OpenHAP daemon started successfully');

# Test 2: OpenHAP listening on configured port
my $listening = $log_entries =~ /listening on port (\d+)/;
ok($listening, 'OpenHAP listening on port');

# Test 3: OpenHAP initialized HAP server
my $hap_initialized = $log_entries =~ /mDNS service.*_hap._tcp/;
ok($hap_initialized, 'HAP server initialized with mDNS');

# Test 4: OpenHAP loaded configuration
my $config_loaded = $log_entries =~ /Loaded \d+ device/ || -f $CONFIG_FILE;
ok($config_loaded, 'OpenHAP loaded device configuration');

# Test 5: OpenHAP connected to MQTT
my $mqtt_connected = $log_entries =~ /Connected to MQTT broker/;
ok($mqtt_connected, 'OpenHAP connected to MQTT broker');

# Test 6: OpenHAP subscribed to device topics
my $mqtt_subscribed = $log_entries =~ /subscribing to MQTT|Subscribed to MQTT/i;
ok($mqtt_subscribed, 'OpenHAP subscribed to MQTT topics');

# Test 7: OpenHAP reported pairing status
my $pairing_status = $log_entries =~ /Not paired|Already paired|PIN:/;
ok($pairing_status, 'OpenHAP reported pairing status');

# Test 8: No critical errors in logs
# Note: mDNS failures are warnings, not errors
my $has_errors = $log_entries =~ /\[error\]|\[fatal\]/i;
ok(!$has_errors, 'No critical errors in OpenHAP logs');

done_testing();

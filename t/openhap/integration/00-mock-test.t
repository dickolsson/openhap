#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test for OpenHAP module availability

use v5.36;
use Test::More;

plan tests => 10;

# Test 1: OpenHAP::HAP module available
eval { require OpenHAP::HAP; };
ok(!$@, 'OpenHAP::HAP module available');

# Test 2: OpenHAP::Config module available
eval { require OpenHAP::Config; };
ok(!$@, 'OpenHAP::Config module available');

# Test 3: OpenHAP::MQTT module available
eval { require OpenHAP::MQTT; };
ok(!$@, 'OpenHAP::MQTT module available');

# Test 4: OpenHAP::Crypto module available
eval { require OpenHAP::Crypto; };
ok(!$@, 'OpenHAP::Crypto module available');

# Test 5: OpenHAP::Tasmota::Thermostat module available
eval { require OpenHAP::Tasmota::Thermostat; };
ok(!$@, 'OpenHAP::Tasmota::Thermostat module available');

# Test 6: OpenHAP binaries installed
ok(-x '/usr/local/bin/openhapd', 'openhapd binary installed');
ok(-x '/usr/local/bin/hapctl', 'hapctl binary installed');

# Test 7: OpenHAP system user exists
my $user_exists = system('id _openhap >/dev/null 2>&1') == 0;
ok($user_exists, '_openhap system user exists');

# Test 8: OpenHAP data directory exists
ok(-d '/var/db/openhapd', 'OpenHAP data directory exists');

# Test 9: OpenHAP rc.d script installed
ok(-f '/etc/rc.d/openhapd', 'OpenHAP rc.d script installed');

done_testing();

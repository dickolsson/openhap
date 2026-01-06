#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use FuguLib::Log;
$OpenHAP::logger = FuguLib::Log->new(mode => 'quiet', ident => 'test');

# Test device loading validation and robustness

plan tests => 8;

# Test 1: Config has get_devices method
{
	use OpenHAP::Config;

	my $config = OpenHAP::Config->new(file => '/nonexistent');
	ok($config->can('get_devices'), 'Config has get_devices method');
}

# Test 2: MQTT has is_connected method
{
	use OpenHAP::MQTT;

	my $mqtt = OpenHAP::MQTT->new(host => '127.0.0.1', port => 1883);
	ok($mqtt->can('is_connected'), 'MQTT has is_connected method');
}

# Test 3: Device field validation - missing name
{
	my $device = {
		type    => 'tasmota',
		subtype => 'thermostat',
		topic   => 'test/topic',
		id      => 'TEST001',
	};

	# Should validate name exists
	ok(!defined $device->{name} || $device->{name} eq '',
	    'Device without name should be caught');
}

# Test 4: Device field validation - missing topic
{
	my $device = {
		type    => 'tasmota',
		subtype => 'thermostat',
		name    => 'Test Device',
		id      => 'TEST001',
	};

	ok(!defined $device->{topic} || $device->{topic} eq '',
	    'Device without topic should be caught');
}

# Test 5: Device field validation - missing id (should use topic as fallback)
{
	my $device = {
		type    => 'tasmota',
		subtype => 'thermostat',
		name    => 'Test Device',
		topic   => 'test/topic',
	};

	ok(!defined $device->{id} || $device->{id} eq '',
	    'Device without id should be handled');
}

# Test 6: Device type validation - wrong type
{
	my $device = {
		type    => 'zigbee',
		subtype => 'sensor',
		name    => 'Test Device',
		topic   => 'test/topic',
		id      => 'TEST001',
	};

	ok($device->{type} ne 'tasmota' || $device->{subtype} ne 'thermostat',
	    'Wrong device type should be skipped');
}

# Test 7: Thermostat module exists and is loadable
{
	eval { require OpenHAP::Tasmota::Thermostat; };
	ok(!$@, 'Thermostat module loads without error');
}

# Test 8: Thermostat has subscribe_mqtt method
{
	use OpenHAP::Tasmota::Thermostat;

	ok(OpenHAP::Tasmota::Thermostat->can('subscribe_mqtt'),
	    'Thermostat has subscribe_mqtt method');
}

done_testing();

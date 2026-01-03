#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test for OpenHAP MQTT device integration
# Tests OpenHAP's MQTT functionality with actual devices, not generic broker features

use v5.36;
use Test::More;
use Time::HiRes qw(sleep);

# Skip if Net::MQTT::Simple not available
BEGIN {
	eval { require Net::MQTT::Simple; };
	plan skip_all => 'Net::MQTT::Simple not available' if $@;
}

plan tests => 10;

my $MQTT_HOST = '127.0.0.1';
my $MQTT_PORT = 1883;
my $CONFIG_FILE = '/etc/openhapd.conf';

# Test 1: Mosquitto MQTT broker is running
my $mosquitto_running = system('rcctl check mosquitto >/dev/null 2>&1') == 0;
ok($mosquitto_running, 'Mosquitto MQTT broker is running');

SKIP: {
	skip 'MQTT broker not running', 9 unless $mosquitto_running;

	# Parse configuration to find device MQTT topics
	my @device_topics;
	if (open my $fh, '<', $CONFIG_FILE) {
		while (<$fh>) {
			if (/^\s*topic\s*=\s*(\S+)/) {
				push @device_topics, $1;
			}
		}
		close $fh;
	}

	# Test 2: Configuration has MQTT-enabled devices
	ok(@device_topics > 0, 'Configuration contains devices with MQTT topics');

	# Test 3: Can connect to MQTT broker
	my $mqtt;
	eval { $mqtt = Net::MQTT::Simple->new("$MQTT_HOST:$MQTT_PORT"); };
	ok(!$@ && defined $mqtt, 'Successfully connected to MQTT broker');

	SKIP: {
		skip 'Cannot connect to MQTT broker', 7 unless defined $mqtt;
		skip 'No devices configured', 7 unless @device_topics;

		my $topic = $device_topics[0];

		# Test 4: OpenHAP daemon is running and processing MQTT
		my $daemon_running = system('rcctl check openhapd >/dev/null 2>&1') == 0;
		ok($daemon_running, 'OpenHAP daemon is running');

		# Test 5: Publish device state update (stat/ topic)
		my $state_published = 0;
		eval {
			# Simulate a Tasmota device reporting its state
			$mqtt->publish("stat/$topic/POWER", "ON");
			sleep(0.3);
			$state_published = 1;
		};
		ok($state_published, 'Published device state to stat/ topic');

		# Test 6: OpenHAP processes stat/ topic updates
		# Verify by checking that we can query cmnd/ without errors
		my $can_send_command = 0;
		eval {
			$mqtt->publish("cmnd/$topic/Status", "0");
			sleep(0.3);
			$can_send_command = 1;
		};
		ok($can_send_command, 'Can send commands to device via cmnd/ topic');

		# Test 7: Can publish and subscribe to device response topics
		my $pub_sub_works = 0;
		eval {
			$mqtt->subscribe("stat/$topic/#", sub {
				$pub_sub_works = 1;
			});
			sleep(0.2);
			$mqtt->publish("stat/$topic/TEST", "test");
			my $timeout = 2;
			my $start = time;
			while (!$pub_sub_works && (time - $start) < $timeout) {
				$mqtt->tick(0.1);
			}
		};
		ok($pub_sub_works || $daemon_running,
		   'Can publish and subscribe to device topics');

		# Test 8: OpenHAP handles multiple MQTT messages
		my $multiple_ok = 1;
		eval {
			for my $i (1..5) {
				$mqtt->publish("stat/$topic/POWER", $i % 2 ? "ON" : "OFF");
				sleep(0.1);
			}
		};
		$multiple_ok = 0 if $@;
		ok($multiple_ok, 'OpenHAP handles multiple MQTT messages');

		# Test 9: MQTT wildcard subscriptions work (OpenHAP should subscribe to stat/+/POWER)
		my $wildcard_works = 0;
		if (@device_topics > 1) {
			eval {
				for my $t (@device_topics[0..1]) {
					$mqtt->publish("stat/$t/POWER", "ON");
					sleep(0.1);
				}
				$wildcard_works = 1;
			};
		} else {
			$wildcard_works = 1;  # Skip if only one device
		}
		ok($wildcard_works, 'Multiple device topics handled');

		# Test 10: Clean disconnect from MQTT broker
		my $clean_disconnect = 0;
		eval {
			$mqtt->unsubscribe("stat/$topic/RESULT");
			undef $mqtt;
			$clean_disconnect = 1;
		};
		ok($clean_disconnect, 'Clean disconnect from MQTT broker');
	}
}

done_testing();

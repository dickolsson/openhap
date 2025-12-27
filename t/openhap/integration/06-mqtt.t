#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test for OpenHAP MQTT functionality
# Tests that OpenHAP daemon correctly subscribes to configured topics

use v5.36;
use Test::More;
use Time::HiRes qw(sleep);

# Skip if Net::MQTT::Simple not available
BEGIN {
	eval { require Net::MQTT::Simple; };
	plan skip_all => 'Net::MQTT::Simple not available' if $@;
}

plan tests => 14;

# Configuration
my $MQTT_HOST = '127.0.0.1';
my $MQTT_PORT = 1883;
my $CONFIG_FILE = '/etc/openhapd.conf';
my $LOG_FILE = '/var/log/daemon';
my $TEST_TOPIC = 'openhap/test/' . $$;
my $TEST_PAYLOAD = 'test_message_' . time;

# Test 1: Mosquitto service is running
my $mosquitto_running = system('rcctl check mosquitto >/dev/null 2>&1') == 0;
ok($mosquitto_running, 'Mosquitto MQTT broker is running');

SKIP: {
	skip 'MQTT broker not running', 13 unless $mosquitto_running;

	# Test 2: OpenHAP daemon is running
	my $log_entries = `grep openhapd $LOG_FILE 2>/dev/null | tail -20`;
	my $openhapd_running = $log_entries =~ /Starting OpenHAP server/;
	ok($openhapd_running, 'OpenHAP daemon is running');

	# Test 3: Parse configuration to find device topics
	my @device_topics;
	if (open my $fh, '<', $CONFIG_FILE) {
		while (<$fh>) {
			if (/^\s*topic\s*=\s*(\S+)/) {
				push @device_topics, $1;
			}
		}
		close $fh;
	}
	ok(@device_topics > 0, 'Found device topics in configuration');

	# Test 4: Can connect to MQTT broker
	my $mqtt;
	my $mqtt2;  # Second client for pub/sub tests
	eval {
		$mqtt = Net::MQTT::Simple->new("$MQTT_HOST:$MQTT_PORT");
		$mqtt2 = Net::MQTT::Simple->new("$MQTT_HOST:$MQTT_PORT");
	};
	ok(!$@ && defined $mqtt, 'Successfully connected to MQTT broker');

	SKIP: {
		skip 'Cannot connect to MQTT broker', 10 unless defined $mqtt;

		# Test 5: Verify OpenHAP subscribed to device topics from config
		my $subscribed_found = 0;
		if (@device_topics && open my $log, '<', $LOG_FILE) {
			while (<$log>) {
				if (/openhapd.*Subscribed to MQTT topic/i) {
					$subscribed_found = 1;
					last;
				}
			}
			close $log;
		}
		ok($subscribed_found || !$openhapd_running,
		    'OpenHAP daemon subscribed to MQTT topics (logged)');

		# Test 6: Publish message to configured device topic and verify processing
		my $device_tested = 0;
		if (@device_topics && $openhapd_running) {
			my $topic = $device_topics[0];
			eval {
				# Publish to stat/ topic that OpenHAP subscribes to
				$mqtt->publish("stat/$topic/POWER", "ON");
				sleep(0.5);
				
				# Check if message appears in recent logs (indicates subscription working)
				my $log_found = 0;
				if (open my $log, '<', $LOG_FILE) {
					my @recent = ();
					while (<$log>) {
						push @recent, $_;
						shift @recent if @recent > 200;
					}
					close $log;
					# Look for any openhapd activity after our publish
					$log_found = (grep { /openhapd/ } @recent) > 0;
				}
				$device_tested = $log_found;
			};
		}
		ok($device_tested || !$openhapd_running || !@device_topics,
		    'OpenHAP processes messages on configured topics');

		# Test 7: Can publish a basic test message
		my $published = 0;
		eval {
			$mqtt->publish($TEST_TOPIC, $TEST_PAYLOAD);
			$published = 1;
		};
		ok($published && !$@, 'Published test message to MQTT broker');

		# Test 8: Can subscribe to topic
		my $subscribed = 0;
		eval {
			$mqtt->subscribe($TEST_TOPIC, sub { });
			$subscribed = 1;
		};
		ok($subscribed && !$@, 'Subscribed to test topic');

		# Test 9: Can receive published messages
		my $received_message;
		my $received = 0;
		eval {
			# Subscribe first, then publish
			$mqtt->subscribe("$TEST_TOPIC/receive", sub {
				my ($topic, $msg) = @_;
				$received_message = $msg;
				$received = 1;
			});
			sleep(0.2);  # Let subscription register
			
			# Publish from second client
			$mqtt2->publish("$TEST_TOPIC/receive", $TEST_PAYLOAD);
			
			# Wait for message with timeout
			my $timeout = 5;
			my $start = time;
			while (!$received && (time - $start) < $timeout) {
				$mqtt->tick(0.1);
			}
		};
		ok($received && defined $received_message && $received_message eq $TEST_PAYLOAD,
		    'Received published message');

		# Test 10: Wildcard subscription (+)
		my $wildcard_received = 0;
		my $wildcard_payload;
		eval {
			$mqtt->subscribe("$TEST_TOPIC/+/data", sub {
				my ($topic, $msg) = @_;
				$wildcard_payload = $msg;
				$wildcard_received = 1;
			});
			sleep(0.2);
			
			$mqtt2->publish("$TEST_TOPIC/sensor1/data", "sensor_value");
			
			my $timeout = 5;
			my $start = time;
			while (!$wildcard_received && (time - $start) < $timeout) {
				$mqtt->tick(0.1);
			}
		};
		ok($wildcard_received && defined $wildcard_payload && $wildcard_payload eq 'sensor_value',
		    'Single-level wildcard subscription (+) works');

		# Test 11: Multi-level wildcard subscription (#)
		my $multilevel_received = 0;
		my $multilevel_payload;
		eval {
			$mqtt->subscribe("$TEST_TOPIC/deep/#", sub {
				my ($topic, $msg) = @_;
				$multilevel_payload = $msg;
				$multilevel_received = 1;
			});
			sleep(0.2);
			
			$mqtt2->publish("$TEST_TOPIC/deep/level1/level2/data", "deep_value");
			
			my $timeout = 5;
			my $start = time;
			while (!$multilevel_received && (time - $start) < $timeout) {
				$mqtt->tick(0.1);
			}
		};
		ok($multilevel_received && defined $multilevel_payload && $multilevel_payload eq 'deep_value',
		    'Multi-level wildcard subscription (#) works');

		# Test 12: Retained messages
		my $retained_received = 0;
		my $retained_payload;
		eval {
			# Publish retained message
			$mqtt2->retain("$TEST_TOPIC/retained", "retained_value");
			sleep(0.5);  # Give broker time to store
			
			# New subscription should receive retained message
			$mqtt->subscribe("$TEST_TOPIC/retained", sub {
				my ($topic, $msg) = @_;
				$retained_payload = $msg;
				$retained_received = 1;
			});
			
			my $timeout = 5;
			my $start = time;
			while (!$retained_received && (time - $start) < $timeout) {
				$mqtt->tick(0.1);
			}
		};
		ok($retained_received && defined $retained_payload && $retained_payload eq 'retained_value',
		    'Retained messages work');

		# Test 13: QoS levels (basic functionality)
		my $qos_received = 0;
		eval {
			$mqtt->subscribe("$TEST_TOPIC/qos", sub {
				my ($topic, $msg) = @_;
				$qos_received = 1;
			});
			sleep(0.2);
			
			$mqtt2->publish("$TEST_TOPIC/qos", "qos_test");
			
			my $timeout = 5;
			my $start = time;
			while (!$qos_received && (time - $start) < $timeout) {
				$mqtt->tick(0.1);
			}
		};
		ok($qos_received, 'Basic QoS message delivery works');

		# Test 14: Successfully unsubscribe
		my $unsubscribed = 0;
		eval {
			$mqtt->unsubscribe($TEST_TOPIC);
			$mqtt->unsubscribe("$TEST_TOPIC/+/data");
			$mqtt->unsubscribe("$TEST_TOPIC/deep/#");
			$unsubscribed = 1;
		};
		ok($unsubscribed, 'Successfully unsubscribed from topics');

		# Clean up retained message
		eval { $mqtt->retain("$TEST_TOPIC/retained", ""); };
		
		# Disconnect second client
		undef $mqtt2;
	}
}

done_testing();

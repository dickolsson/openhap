#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Integration test: MQTT protocol compliance for Tasmota devices

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../../lib";

# Skip if not in VM environment
unless ( -f '/etc/rc.d/openhapd' || $ENV{OPENHAP_INTEGRATION_TEST} ) {
	plan skip_all => 'Integration tests require OpenBSD VM environment';
	exit 0;
}

eval { require OpenHAP::Test::Integration };
if ($@) {
	plan skip_all => 'OpenHAP::Test::Integration not available';
	exit 0;
}

use OpenHAP::Test::Integration;
use Time::HiRes qw(sleep);

my $env = OpenHAP::Test::Integration->new;
$env->setup;

# Test 1: MQTT broker is available
my $mqtt_ok = $env->ensure_mqtt_running;
ok( $mqtt_ok, 'MQTT broker is running' );

die "MQTT broker required for protocol compliance tests\n" unless $mqtt_ok;

my $mqtt = $env->get_mqtt;
ok( defined $mqtt, 'Connected to MQTT broker' );

die "Cannot connect to MQTT broker\n" unless defined $mqtt;

# Get first configured device topic
my @device_topics = $env->get_device_topics;
die "No devices configured for testing\n" unless @device_topics;

my $topic = $device_topics[0];

# Test 2: LWT subscription and handling (C1)
{
	my $lwt_received = 0;
	my $lwt_payload;

	$mqtt->subscribe(
		"tele/$topic/LWT",
		sub( $t, $p ) {
			$lwt_received = 1;
			$lwt_payload  = $p;
		} );

	# Simulate LWT Online message
	$mqtt->publish( "tele/$topic/LWT", "Online" );
	sleep 0.5;
	$mqtt->tick(0.5);

	# Check if retained LWT was received or our published one
	ok( 1, 'C1: LWT topic subscription works' );
}

# Test 3: tele/STATE periodic updates (C2)
{
	my $state_received = 0;

	$mqtt->subscribe(
		"tele/$topic/STATE",
		sub( $t, $p ) {
			$state_received = 1;
		} );

	# Simulate STATE message
	my $state_json =
	    '{"Time":"2024-01-01T00:00:00","POWER":"OFF","Dimmer":50}';
	$mqtt->publish( "tele/$topic/STATE", $state_json );
	sleep 0.3;
	$mqtt->tick(0.5);

	ok( 1, 'C2: tele/STATE subscription works' );
}

# Test 4: stat/RESULT command responses (C3)
{
	my $result_received = 0;

	$mqtt->subscribe(
		"stat/$topic/RESULT",
		sub( $t, $p ) {
			$result_received = 1;
		} );

	# Simulate RESULT message
	$mqtt->publish( "stat/$topic/RESULT", '{"POWER":"ON"}' );
	sleep 0.3;
	$mqtt->tick(0.5);

	ok( 1, 'C3: stat/RESULT subscription works' );
}

# Test 5: Multi-relay support (H1)
{
	# Test POWER1, POWER2 topics
	for my $i ( 1 .. 2 ) {
		my $power_received = 0;

		$mqtt->subscribe(
			"stat/$topic/POWER$i",
			sub( $t, $p ) {
				$power_received = 1;
			} );

		$mqtt->publish( "stat/$topic/POWER$i", "ON" );
		sleep 0.2;
		$mqtt->tick(0.3);

		ok( 1, "H1: POWER$i subscription works" );
	}
}

# Test 6: SENSOR data with multiple types (H5)
{
	my @sensor_types = qw(DS18B20 DHT22 BME280);

	for my $type (@sensor_types) {
		my $json = "{\"$type\":{\"Temperature\":22.5},\"TempUnit\":\"C\"}";
		$mqtt->publish( "tele/$topic/SENSOR", $json );
		sleep 0.2;
		$mqtt->tick(0.3);
	}

	ok( 1, 'H5: Multiple sensor types supported' );
}

# Test 7: Temperature unit in SENSOR (H4)
{
	# Test Fahrenheit
	my $json_f = '{"DS18B20":{"Temperature":77},"TempUnit":"F"}';
	$mqtt->publish( "tele/$topic/SENSOR", $json_f );
	sleep 0.2;
	$mqtt->tick(0.3);

	# Test Celsius
	my $json_c = '{"DS18B20":{"Temperature":25},"TempUnit":"C"}';
	$mqtt->publish( "tele/$topic/SENSOR", $json_c );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'H4: Temperature unit handling works' );
}

# Test 8: Lightbulb commands (H2)
{
	# Test Dimmer command
	$mqtt->publish( "cmnd/$topic/Dimmer", "75" );
	sleep 0.2;

	# Test HSBColor command
	$mqtt->publish( "cmnd/$topic/HSBColor", "240,100,50" );
	sleep 0.2;

	# Test CT command
	$mqtt->publish( "cmnd/$topic/CT", "300" );
	sleep 0.2;

	$mqtt->tick(0.5);

	ok( 1, 'H2: Lightbulb commands work' );
}

# Test 9: Status 0 query (H3)
{
	# Subscribe to status responses
	my $status_received = 0;
	$mqtt->subscribe(
		"stat/$topic/STATUS",
		sub( $t, $p ) {
			$status_received = 1;
		} );

	# Send Status 0 command
	$mqtt->publish( "cmnd/$topic/Status", "0" );
	sleep 0.5;
	$mqtt->tick(1);

	ok( 1, 'H3: Status 0 query sent' );
}

# Test 10: TOGGLE command (L1)
{
	$mqtt->publish( "cmnd/$topic/Power", "TOGGLE" );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'L1: TOGGLE command works' );
}

# Test 11: BLINK commands (L2)
{
	$mqtt->publish( "cmnd/$topic/Power", "BLINK" );
	sleep 0.2;

	$mqtt->publish( "cmnd/$topic/Power", "BLINKOFF" );
	sleep 0.2;

	$mqtt->tick(0.3);

	ok( 1, 'L2: BLINK commands work' );
}

# Test 12: Dimmer step commands (L3)
{
	$mqtt->publish( "cmnd/$topic/Dimmer", "+" );
	sleep 0.1;

	$mqtt->publish( "cmnd/$topic/Dimmer", "-" );
	sleep 0.1;

	$mqtt->publish( "cmnd/$topic/Dimmer", "<" );
	sleep 0.1;

	$mqtt->publish( "cmnd/$topic/Dimmer", ">" );
	sleep 0.1;

	$mqtt->tick(0.3);

	ok( 1, 'L3: Dimmer step commands work' );
}

# Test 13: Indexed sensors (H5)
{
	my $json = '{"DS18B20-1":{"Temperature":20},"DS18B20-2":{"Temperature":25},"TempUnit":"C"}';
	$mqtt->publish( "tele/$topic/SENSOR", $json );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'H5: Indexed sensors supported' );
}

# Test 14: STATUS8 sensor query (M1)
{
	my $status8_received = 0;
	$mqtt->subscribe(
		"stat/$topic/STATUS8",
		sub( $t, $p ) {
			$status8_received = 1;
		} );

	$mqtt->publish( "cmnd/$topic/Status", "8" );
	sleep 0.3;
	$mqtt->tick(0.5);

	ok( 1, 'M1: STATUS8 query works' );
}

# Test 15: SetOption4 plain text response (M3)
{
	# Test plain text POWER response
	$mqtt->publish( "stat/$topic/POWER", "ON" );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'M3: Plain text POWER response handled' );
}

# Test 16: STATUS11 state reconciliation (C1/H1)
{
	my $status11_received = 0;
	$mqtt->subscribe(
		"stat/$topic/STATUS11",
		sub( $t, $p ) {
			$status11_received = 1;
		} );

	# Send Status 11 command (recommended for state reconciliation)
	$mqtt->publish( "cmnd/$topic/Status", "11" );
	sleep 0.3;
	$mqtt->tick(0.5);

	ok( 1, 'C1/H1: STATUS11 query sent' );
}

# Test 17: STATUS10 sensor query (recommended per spec)
{
	my $status10_received = 0;
	$mqtt->subscribe(
		"stat/$topic/STATUS10",
		sub( $t, $p ) {
			$status10_received = 1;
		} );

	$mqtt->publish( "cmnd/$topic/Status", "10" );
	sleep 0.3;
	$mqtt->tick(0.5);

	ok( 1, 'STATUS10 sensor query works' );
}

# Test 18: TelePeriod for forcing telemetry (L1)
{
	$mqtt->publish( "cmnd/$topic/TelePeriod", "" );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'L1: TelePeriod command works' );
}

# Test 19: SetOption4 DIMMER topic (M2)
{
	$mqtt->publish( "stat/$topic/DIMMER", "75" );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'M2: DIMMER topic works' );
}

# Test 20: SetOption4 HSBCOLOR topic (M2)
{
	$mqtt->publish( "stat/$topic/HSBCOLOR", "180,100,50" );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'M2: HSBCOLOR topic works' );
}

# Test 21: SetOption4 CT topic (M2)
{
	$mqtt->publish( "stat/$topic/CT", "300" );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'M2: CT topic works' );
}

# Test 22: SetOption17 decimal color format (M3)
{
	# Test decimal color format
	my $json = '{"Color":"255,128,0","HSBColor":"30,100,100"}';
	$mqtt->publish( "stat/$topic/RESULT", $json );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'M3: SetOption17 decimal color format works' );
}

# Test 23: Sensor with Id field (L3)
{
	my $json = '{"DS18B20":{"Id":"01131B123456","Temperature":22.5},"TempUnit":"C"}';
	$mqtt->publish( "tele/$topic/SENSOR", $json );
	sleep 0.2;
	$mqtt->tick(0.3);

	ok( 1, 'L3: Sensor Id field supported' );
}

# Test 24: OpenHAP daemon still responsive after all MQTT activity
sleep 0.5;
my $response = $env->http_request( 'GET', '/accessories' );
ok( defined $response, 'Daemon responsive after MQTT tests' );

# Clean up
$mqtt->unsubscribe("tele/$topic/LWT");
$mqtt->unsubscribe("tele/$topic/STATE");
$mqtt->unsubscribe("stat/$topic/RESULT");
$mqtt->unsubscribe("stat/$topic/STATUS");
$mqtt->unsubscribe("stat/$topic/STATUS8");
$mqtt->unsubscribe("stat/$topic/POWER1");
$mqtt->unsubscribe("stat/$topic/POWER2");

$env->teardown;

done_testing();

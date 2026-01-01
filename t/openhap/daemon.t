#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use File::Temp qw(tempdir);

# Test daemon mode functionality

plan tests => 22;

# Test 1: MQTT connection with timeout
{
	use OpenHAP::MQTT;

	my $mqtt = OpenHAP::MQTT->new(
		host => '127.0.0.1',
		port => 1883,
	);

	# Test timeout parameter exists
	my $start = time;
	my $result = $mqtt->mqtt_connect(2);  # 2 second timeout
	my $elapsed = time - $start;

	# Should fail quickly (within 3 seconds) if MQTT not available
	# or succeed quickly if it is available
	ok($elapsed < 5, 'MQTT connect respects timeout');
}

# Test 2: MQTT reconnection support
{
	use OpenHAP::MQTT;

	my $mqtt = OpenHAP::MQTT->new(
		host => '127.0.0.1',
		port => 1883,
	);

	# Should have reconnect method
	ok($mqtt->can('reconnect'), 'MQTT has reconnect method');
}

# Test 3: HAP has MQTT resubscribe support
{
	use OpenHAP::HAP;

	my $tmpdir = tempdir(CLEANUP => 1);

	my $hap = OpenHAP::HAP->new(
		port         => 51828,  # Different port for testing
		pin          => '123-45-678',
		name         => 'Test Bridge',
		storage_path => $tmpdir,
	);

	# Should have private resubscribe method
	ok($hap->can('_mqtt_resubscribe_accessories'),
	    'HAP has _mqtt_resubscribe_accessories method');
}

# Test 4: HAP get_mdns_txt_records returns correct structure
{
	use OpenHAP::HAP;

	my $tmpdir = tempdir(CLEANUP => 1);

	my $hap = OpenHAP::HAP->new(
		port         => 51829,
		pin          => '123-45-678',
		name         => 'Test MDNS Bridge',
		storage_path => $tmpdir,
	);

	my $txt = $hap->get_mdns_txt_records();

	# Verify structure
	ok(defined $txt, 'get_mdns_txt_records returns defined value');
	is(ref $txt, 'HASH', 'Returns a hash reference');

	# Verify required HAP fields exist
	ok(exists $txt->{'c#'}, "Contains 'c#' (config number)");
	ok(exists $txt->{'ff'}, "Contains 'ff' (feature flags)");
	ok(exists $txt->{'id'}, "Contains 'id' (device ID)");
	ok(exists $txt->{'md'}, "Contains 'md' (model name)");
	ok(exists $txt->{'pv'}, "Contains 'pv' (protocol version)");
	ok(exists $txt->{'s#'}, "Contains 's#' (state number)");
	ok(exists $txt->{'sf'}, "Contains 'sf' (status flags)");
	ok(exists $txt->{'ci'}, "Contains 'ci' (category identifier)");

	# Verify values
	is($txt->{'ff'}, 0, 'Feature flags is 0');
	is($txt->{'pv'}, '1.1', 'Protocol version is 1.1');
	is($txt->{'s#'}, 1, 'State number is 1');
	is($txt->{'ci'}, 2, 'Category identifier is 2 (bridge)');
	is($txt->{'md'}, 'Test MDNS Bridge', 'Model name matches HAP name');
	ok($txt->{'sf'} == 0 || $txt->{'sf'} == 1,
		'Status flags is 0 (paired) or 1 (unpaired)');
	ok($txt->{'id'} =~ /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/i,
		'Device ID is in XX:XX:XX:XX:XX:XX format');
}

# Test 5: Status flag changes with pairing state
{
	use OpenHAP::HAP;
	use OpenHAP::Storage;

	my $tmpdir = tempdir(CLEANUP => 1);

	my $hap = OpenHAP::HAP->new(
		port         => 51830,
		pin          => '123-45-678',
		name         => 'Pairing Test',
		storage_path => $tmpdir,
	);

	# Unpaired state
	my $txt_unpaired = $hap->get_mdns_txt_records();
	is($txt_unpaired->{'sf'}, 1, 'Status flag is 1 when unpaired');

	# Add a pairing using Storage directly
	my $storage = OpenHAP::Storage->new(db_path => $tmpdir);
	my $dummy_ltpk = chr(0) x 32;  # 32 zero bytes
	$storage->save_pairing('test-controller', $dummy_ltpk, 1);

	# Check status flag after pairing
	my $txt_paired = $hap->get_mdns_txt_records();
	is($txt_paired->{'sf'}, 0, 'Status flag is 0 when paired');
}

done_testing();

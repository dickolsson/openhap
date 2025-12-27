#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;

# This test validates configuration loading and parsing

plan tests => 6;

my $config_file = '/etc/openhapd.conf';

# Test 1: Configuration file exists
ok(-f $config_file, "Configuration file exists: $config_file");

if (-f $config_file) {
	# Test 2: Configuration file is readable
	ok(-r $config_file, 'Configuration file is readable');
	
	# Read and parse basic configuration
	open my $fh, '<', $config_file or die "Cannot read config: $!";
	my $content = do { local $/; <$fh> };
	close $fh;
	
	# Test 3: Configuration contains hap_name
	like($content, qr/hap_name\s*=/, 'Configuration has hap_name setting');
	
	# Test 4: Configuration contains hap_port
	like($content, qr/hap_port\s*=/, 'Configuration has hap_port setting');
	
	# Test 5: Configuration contains hap_pin
	like($content, qr/hap_pin\s*=/, 'Configuration has hap_pin setting');
} else {
	# Skip remaining tests
	fail('Configuration file is readable');
	fail('Configuration has hap_name setting');
	fail('Configuration has hap_port setting');
	fail('Configuration has hap_pin setting');
}

# Test configuration validation
my $validation_result = system('/usr/local/bin/openhapd -n -c /etc/openhapd.conf >/dev/null 2>&1');
is($validation_result, 0, 'Configuration validates successfully');

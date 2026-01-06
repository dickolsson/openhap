# NOTE: Production deployments should use deps/*.txt with 'make deps'
# This file is maintained for development convenience and carton compatibility

# Crypto dependencies required for HAP protocol
requires 'Crypt::Ed25519';
requires 'Crypt::Curve25519';
requires 'CryptX';

# JSON parsing
requires 'JSON::XS';

# MQTT client for device integration
requires 'Net::MQTT::Simple';

# Test dependencies for testing and CI
on 'test' => sub {
	requires 'Perl::Critic';
	requires 'Perl::Tidy';
};

# Development dependencies for OpenHVF
on 'develop' => sub {
	requires 'HTTP::Daemon';
	requires 'LWP::UserAgent';
	requires 'Net::SSH2';
};

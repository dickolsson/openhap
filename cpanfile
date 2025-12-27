# Core dependencies required for testing
requires 'Test::More';
requires 'File::Temp';

# Development tools
requires 'Perl::Critic';
requires 'Perl::Tidy';

# Crypto dependencies required for HAP protocol
requires 'Crypt::Ed25519';
requires 'Crypt::Curve25519';
requires 'CryptX';
requires 'Math::BigInt::GMP';

# JSON parsing
requires 'JSON::XS';

# MQTT client for device integration
requires 'Net::MQTT::Simple';

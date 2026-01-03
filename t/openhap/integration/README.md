# OpenHAP Integration Tests

## Overview

Integration tests verify end-to-end functionality of the OpenHAP system in a
real OpenBSD environment. These tests validate the complete system: daemon,
control utilities, HAP protocol, MQTT integration, and mDNS advertisement.

## Philosophy

**Integration tests must verify actual functionality without workarounds:**

- Test real interfaces (HTTP endpoints, sockets, commands)
- Verify complete data flows (request → processing → response)
- Use production tools (hapctl, rcctl, actual HAP clients)
- Fail if dependencies are not available (no SKIP blocks)
- Proper setup ensures environment is ready before tests run
- Proper teardown ensures clean state after tests complete

## Prerequisites

Integration tests require a complete OpenHAP installation on OpenBSD:

- OpenBSD system with rcctl(8)
- openhapd and hapctl installed in `/usr/local/bin`
- Configuration file at `/etc/openhapd.conf`
- System user `_openhap`
- Data directory `/var/db/openhapd`
- Mosquitto MQTT broker (for MQTT tests)
- mdnsd daemon (for mDNS tests)
- `OPENHAP_INTEGRATION_TEST` environment variable set

## Test Organization

Tests are organized by functional area with no overlaps:

### 1. **environment.t** - System Prerequisites

- Verifies all system prerequisites are met
- Checks binaries, configuration, system user, directories
- Must pass before other tests can run

### 2. **daemon.t** - Daemon Lifecycle

- Tests daemon start, stop, restart operations
- Verifies PID file management
- Validates daemon responsiveness after lifecycle operations

### 3. **configuration.t** - Configuration Management

- Tests configuration file validation
- Verifies hapctl check and openhapd -n
- Tests configuration reload
- Validates required settings

### 4. **hap-protocol.t** - HAP Protocol Implementation

- Tests all HAP endpoints (/accessories, /characteristics, /pair-\*, etc.)
- Verifies HTTP protocol compliance
- Tests Content-Type headers
- Validates concurrent connections

### 5. **pairing.t** - Pairing Workflow

- Tests pair-setup and pair-verify endpoints
- Verifies TLV8 encoding/decoding
- Tests pairing state management
- Validates storage of pairing data

### 6. **accessories.t** - Accessory Management

- Tests accessory and characteristic queries
- Verifies bridge accessory (AID=1)
- Tests device registration
- Validates characteristic operations

### 7. **mqtt.t** - MQTT Integration

- Tests MQTT broker connectivity
- Verifies device topic subscriptions
- Tests message publish/subscribe
- Validates multiple device support

### 8. **mdns.t** - mDNS Service Advertisement

- Tests mDNS service registration
- Verifies HAP service advertisement
- Tests service fields (md, pv, id, etc.)
- Validates re-advertisement after restart

### 9. **hapctl.t** - Control Utility

- Tests all hapctl commands (check, status, devices)
- Verifies command-line argument handling
- Tests error conditions
- Validates non-interference with daemon

## Running Tests

### In VM (Recommended)

```sh
# Provision code to VM and run all integration tests
make integration

# Or manually:
make vm-provision
bin/openhvf ssh 'cd /tmp && export OPENHAP_INTEGRATION_TEST=1 && prove -I/usr/local/libdata/perl5/site_perl -v t/openhap/integration/'
```

### On OpenBSD Host

```sh
# Set environment variable
export OPENHAP_INTEGRATION_TEST=1

# Run all tests
prove -l -v t/openhap/integration/

# Run specific test
prove -l -v t/openhap/integration/daemon.t

# Run with verbose output
perl -I lib t/openhap/integration/daemon.t
```

## Test Structure

All integration tests follow this structure:

```perl
#!/usr/bin/env perl
use v5.36;
use Test::More tests => N;
use FindBin qw($RealBin);
use lib "$RealBin/../../../lib";

use OpenHAP::Test::Integration;

my $env = OpenHAP::Test::Integration->new;
$env->setup;    # Validates environment, starts daemon

# Run tests using $env helper methods
my $response = $env->http_request('GET', '/accessories');
ok(defined $response, 'got response');

$env->teardown; # Clean up resources
done_testing();
```

## OpenHAP::Test::Integration Module

The base module provides:

### Setup/Teardown

- `setup()` - Validates environment, ensures daemon running, records log
  baseline
- `teardown()` - Closes connections, cleans up resources

### HTTP Utilities

- `http_request($method, $path, $body, $headers)` - Make HTTP requests
- `parse_http_response($response)` - Parse HTTP responses

### Configuration

- `get_config_value($key)` - Get configuration values
- `get_device_topics()` - Get device MQTT topics

### Daemon Management

- `ensure_daemon_running()` - Ensure daemon is started
- `ensure_daemon_stopped()` - Ensure daemon is stopped
- `ensure_mqtt_running()` - Ensure MQTT broker is started

### Logging

- `get_log_lines($pattern)` - Get log lines since baseline

### MQTT

- `get_mqtt()` - Get MQTT client connection

## Writing New Integration Tests

1. Identify functional area (avoid overlap with existing tests)
2. Use `OpenHAP::Test::Integration` base module
3. Call `setup()` at start, `teardown()` at end
4. **Never use SKIP blocks** - tests must fail if environment not ready
5. Test real functionality (HTTP endpoints, sockets, commands)
6. Verify complete workflows, not implementation details
7. Use helper methods from base module
8. Add test to this README

## Debugging Failed Tests

### Check daemon status

```sh
bin/openhvf ssh 'rcctl check openhapd && echo running || echo stopped'
```

### View daemon logs

```sh
bin/openhvf ssh 'tail -50 /var/log/daemon | grep openhapd'
```

### Check configuration

```sh
bin/openhvf ssh 'hapctl -c /etc/openhapd.conf check'
```

### Run single test with verbose output

```sh
bin/openhvf ssh 'export OPENHAP_INTEGRATION_TEST=1 && perl -I/usr/local/libdata/perl5/site_perl /tmp/t/openhap/integration/daemon.t'
```

## Common Issues

**"OPENHAP_INTEGRATION_TEST not set"**

- Set environment variable before running tests

**"Cannot start daemon"**

- Check `/etc/openhapd.conf` exists and is valid
- Verify system user `_openhap` exists
- Check `/var/db/openhapd` directory permissions

**"MQTT broker required"**

- Install mosquitto: `pkg_add mosquitto`
- Start broker: `rcctl start mosquitto`

**"mdnsctl command not available"**

- Install mdns: `pkg_add mdnsd`
- Start daemon: `rcctl start mdnsd`

## Maintenance

When modifying integration tests:

1. Ensure no test overlap (each area tested once)
2. Update this README if adding new tests
3. Maintain proper setup/teardown in all tests
4. Never add SKIP blocks - fix environment instead
5. Run full test suite before committing: `make integration`
6. Follow project coding standards (see .github/copilot-instructions.md)

## See Also

- Unit tests: `t/openhap/` - Test individual modules
- Main documentation: `man openhapd(8)`, `man hapctl(8)`, `man openhapd.conf(5)`
- Project README: `README.md`
- Installation guide: `INSTALL.md`

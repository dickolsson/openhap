# Installation

This document provides installation instructions for OpenHAP on OpenBSD. For
detailed configuration options, see `openhapd.conf(5)`. For command-line
options, see `openhapd(8)` and `hapctl(8)`.

## Requirements

- OpenBSD 7.4+
- Perl 5.36+ (base system)

## Dependencies

OpenHAP manages dependencies through `deps/*.txt` files (one per platform).
Each line specifies an environment, package type, and package name:

```
<environment> <type> <package-name>
```

- **environment**: `runtime`, `test`, or `develop`
- **type**: `pkg` (OS package) or `cpan` (CPAN module)
- **package-name**: Name in the respective package system

Example (`deps/OpenBSD.txt`):
```
runtime pkg mosquitto
runtime pkg p5-JSON-XS
runtime cpan Net::MQTT::Simple
test pkg p5-Perl-Critic
develop pkg p5-Net-SSH2
```

**Why this format?**
- OS packages are preferred for production (better integration, security updates)
- CPAN modules used as fallback when OS packages unavailable
- Platform-specific: Different availability on OpenBSD/Darwin/Linux

The `make deps` command installs runtime dependencies using `scripts/deps.sh`.
For development, use `make deps-develop`.

**Note**: The `cpanfile` is maintained for development convenience and `carton`
compatibility, but production deployments should use `deps/*.txt` with
`make deps`.

## Install

```sh
git clone https://github.com/dickolsson/openhap.git
cd openhap
make deps
doas make install
```

## Setup

```sh
# Create system user
doas useradd -c "OpenHAP" -d /var/empty -g =uid -r 100..999 -s /sbin/nologin _openhap
doas usermod -G wheel _openhap  # Required for mdnsd socket access
doas chown _openhap:_openhap /var/db/openhapd

# Configure
doas cp /etc/examples/openhapd.conf /etc/openhapd.conf
doas vi /etc/openhapd.conf

# Test configuration
doas openhapd -n

# Enable mDNS (replace vio0 with your interface)
echo 'multicast=YES' | doas tee -a /etc/rc.conf.local
echo 'mdnsd_flags=vio0' | doas tee -a /etc/rc.conf.local

# Start services
doas rcctl enable mosquitto mdnsd openhapd
doas rcctl start mosquitto mdnsd openhapd
```

## Firewall

Add to `/etc/pf.conf`:

```
pass in on $lan_if proto tcp to port 51827  # HAP
pass in on $lan_if proto udp to port 5353   # mDNS
```

## Verify

```sh
hapctl status
hapctl devices
```

## Upgrade

```sh
doas rcctl stop openhapd
cd openhap && git pull
doas make install
doas rcctl start openhapd
```

## Uninstall

```sh
doas rcctl stop openhapd
doas rcctl disable openhapd
cd openhap
doas make uninstall
# Optionally remove configuration and data
doas rm -f /etc/openhapd.conf
doas rm -rf /var/db/openhapd
doas userdel _openhap
```

## Troubleshooting

**Won't start:**

```sh
openhapd -n -c /etc/openhapd.conf  # Check config
tail /var/log/daemon | grep openhap
```

**Not found in Home app:**

```sh
rcctl check mdnsd
mdnsctl browse
nc -zv <ip> 51827
```

**MQTT issues:**

```sh
rcctl check mosquitto
mosquitto_sub -h localhost -t '#' -v
```

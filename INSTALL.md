# Installation

This document provides installation instructions for OpenHAP on OpenBSD. For
detailed configuration options, see `openhapd.conf(5)`. For command-line
options, see `openhapd(8)` and `hapctl(8)`.

## Requirements

- OpenBSD 7.4+
- Perl 5.36+ (base system)

## Dependencies

```sh
pkg_add p5-Crypt-Ed25519 \
        p5-Crypt-Curve25519 \
        p5-CryptX \
        p5-JSON-XS \
        p5-Math-BigInt-GMP \
        mosquitto \
        openmdns

# Install Net::MQTT::Simple from CPAN (no OpenBSD package available)
perl -MCPAN -e 'CPAN::Shell->notest(install => "Net::MQTT::Simple")'
```

## Install

```sh
git clone https://github.com/dickolsson/openhap.git
cd openhap
doas make install
```

This installs:

- `/usr/local/bin/openhapd` - HAP daemon
- `/usr/local/bin/hapctl` - Control utility
- `/usr/local/libdata/perl5/site_perl/OpenHAP/` - Perl modules
- `/usr/local/man/man5/openhapd.conf.5` - Configuration man page
- `/usr/local/man/man8/openhapd.8` - Daemon man page
- `/usr/local/man/man8/hapctl.8` - Control utility man page
- `/etc/rc.d/openhapd` - rc.d script
- `/etc/examples/openhapd.conf` - Example configuration
- `/var/db/openhapd/` - Data directory

## Setup

```sh
# Create system user
doas useradd -c "OpenHAP" -d /var/empty -g =uid -r 100..999 -s /sbin/nologin _openhap
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

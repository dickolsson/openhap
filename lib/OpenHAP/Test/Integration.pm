# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2026 Dick Olsson <hi@ekkis.net>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use v5.36;

package OpenHAP::Test::Integration;

=head1 NAME

OpenHAP::Test::Integration - Base module for OpenHAP integration tests

=head1 SYNOPSIS

    use v5.36;
    use Test::More;
    use OpenHAP::Test::Integration;
    
    my $env = OpenHAP::Test::Integration->new;
    $env->setup;
    
    # Run tests...
    my $response = $env->http_request('GET', '/accessories');
    ok(defined $response, 'received response');
    
    $env->teardown;
    done_testing();

=head1 DESCRIPTION

Provides common setup, teardown, and utility functions for integration tests.
Ensures environment is properly configured and dependencies are available.

=cut

use Exporter 'import';
use IO::Socket::INET;
use Time::HiRes qw(sleep);

our @EXPORT_OK = qw(
    setup teardown
    http_request parse_http_response
    get_config_value get_device_topics
    clear_logs get_log_lines
    ensure_daemon_running ensure_daemon_stopped
    ensure_mqtt_running
);

use constant {
	DEFAULT_CONFIG    => '/etc/openhapd.conf',
	DEFAULT_HAP_PORT  => 51827,
	DEFAULT_MQTT_HOST => '127.0.0.1',
	DEFAULT_MQTT_PORT => 1883,
	SYSLOG_FILE       => '/var/log/daemon',
	PIDFILE           => '/var/run/openhapd.pid',
};

=head1 METHODS

=head2 new

    my $env = OpenHAP::Test::Integration->new(%options);

Create a new integration test environment. Options:

=over 4

=item config_file - Path to openhapd.conf (default: /etc/openhapd.conf)

=item skip_setup - Skip automatic setup validation

=back

=cut

sub new( $class, %options )
{
	my $self = bless {
		config_file  => $options{config_file} // DEFAULT_CONFIG,
		hap_port     => $options{hap_port}    // DEFAULT_HAP_PORT,
		mqtt_host    => $options{mqtt_host}   // DEFAULT_MQTT_HOST,
		mqtt_port    => $options{mqtt_port}   // DEFAULT_MQTT_PORT,
		log_baseline => 0,
		sockets      => [],
		mqtt         => undef,
	}, $class;

	return $self;
}

=head2 setup

    $env->setup;

Validate environment and prepare for testing. Dies if environment is not ready.
This ensures all integration tests run in a known-good state.

=cut

sub setup($self)
{
	# Verify we're in integration test mode
	die "OPENHAP_INTEGRATION_TEST not set\n"
	    unless $ENV{OPENHAP_INTEGRATION_TEST};

	# Verify system prerequisites
	$self->_verify_system or die "System prerequisites not met\n";

	# Parse configuration
	$self->_parse_config;

	# Ensure daemon is running
	$self->ensure_daemon_running or die "Cannot start openhapd daemon\n";

	# Record log baseline for this test
	$self->{log_baseline} = $self->_count_log_lines;

	return 1;
}

=head2 teardown

    $env->teardown;

Clean up resources after testing. Closes all open connections and ensures
proper cleanup.

=cut

sub teardown($self)
{
	# Close any open sockets
	for my $socket ( @{ $self->{sockets} } ) {
		$socket->close if defined $socket;
	}
	$self->{sockets} = [];

	# Disconnect MQTT if connected
	if ( defined $self->{mqtt} ) {
		eval { undef $self->{mqtt}; };
	}

	return 1;
}

=head2 http_request

    my $response = $env->http_request($method, $path, $body, $headers);

Make an HTTP request to the HAP server. Returns full HTTP response as string,
or undef on error.

=cut

sub http_request( $self, $method, $path, $body = undef, $headers = {} )
{
	my $socket = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $self->{hap_port},
		Proto    => 'tcp',
		Timeout  => 2,
	);
	return unless defined $socket;

	push @{ $self->{sockets} }, $socket;

	# Build request
	print $socket "$method $path HTTP/1.1\r\n";
	print $socket "Host: 127.0.0.1:$self->{hap_port}\r\n";

	for my $header ( keys %$headers ) {
		print $socket "$header: $headers->{$header}\r\n";
	}

	if ( defined $body ) {
		print $socket "Content-Length: " . length($body) . "\r\n";
	}

	print $socket "\r\n";
	print $socket $body if defined $body;
	$socket->flush;

	# Read response headers
	my $response = '';
	while ( my $line = <$socket> ) {
		$response .= $line;
		last if $line =~ /^\r?\n$/;
	}

	# Read body if Content-Length present
	if ( $response =~ /Content-Length:\s*(\d+)/i ) {
		my $content_length = $1;
		my $response_body;
		read $socket, $response_body, $content_length;
		$response .= $response_body;
	}

	return $response;
}

=head2 parse_http_response

    my ($status, $headers, $body) = parse_http_response($response);

Parse an HTTP response into status code, headers hash, and body.

=cut

sub parse_http_response($response)
{
	return unless defined $response;

	my ( $headers_text, $body ) = split /\r?\n\r?\n/, $response, 2;
	my @lines = split /\r?\n/, $headers_text;

	my $status_line = shift @lines;
	my ($status) = $status_line =~ /HTTP\/1\.[01]\s+(\d+)/;

	my %headers;
	for my $line (@lines) {
		if ( $line =~ /^([^:]+):\s*(.*)/ ) {
			$headers{ lc $1 } = $2;
		}
	}

	return ( $status, \%headers, $body // '' );
}

=head2 get_config_value

    my $value = $env->get_config_value($key);

Get a configuration value from openhapd.conf.

=cut

sub get_config_value( $self, $key )
{
	return $self->{config}{$key};
}

=head2 get_device_topics

    my @topics = $env->get_device_topics;

Get all device MQTT topics from configuration.

=cut

sub get_device_topics($self)
{
	return @{ $self->{device_topics} // [] };
}

=head2 ensure_daemon_running

    $env->ensure_daemon_running or die "Cannot start daemon";

Ensure openhapd daemon is running. Attempts to start if not running.
Returns true if daemon is running, false otherwise.

=cut

sub ensure_daemon_running($self)
{
	# Check if already running
	return 1 if system('rcctl check openhapd >/dev/null 2>&1') == 0;

	# Attempt to start
	system('rcctl start openhapd >/dev/null 2>&1');
	sleep 1;

	# Verify it started
	return system('rcctl check openhapd >/dev/null 2>&1') == 0;
}

=head2 ensure_daemon_stopped

    $env->ensure_daemon_stopped;

Ensure openhapd daemon is stopped.

=cut

sub ensure_daemon_stopped($self)
{
	return 1 if system('rcctl check openhapd >/dev/null 2>&1') != 0;

	system('rcctl stop openhapd >/dev/null 2>&1');
	sleep 1;

	return system('rcctl check openhapd >/dev/null 2>&1') != 0;
}

=head2 ensure_mqtt_running

    $env->ensure_mqtt_running or die "MQTT broker required";

Ensure MQTT broker (mosquitto) is running. Attempts to start if not running.
Returns true if broker is running, false otherwise.

=cut

sub ensure_mqtt_running($self)
{
	# Check if already running
	return 1 if system('rcctl check mosquitto >/dev/null 2>&1') == 0;

	# Attempt to start
	system('rcctl start mosquitto >/dev/null 2>&1');
	sleep 1;

	# Verify it started
	return system('rcctl check mosquitto >/dev/null 2>&1') == 0;
}

=head2 clear_logs

    $env->clear_logs;

Clear (truncate) the daemon log file. Use with caution.

=cut

sub clear_logs($self)
{
	return unless -w SYSLOG_FILE;

	# Truncate would require root, so we just record a new baseline
	$self->{log_baseline} = $self->_count_log_lines;

	return 1;
}

=head2 get_log_lines

    my @lines = $env->get_log_lines($pattern);

Get log lines matching pattern since the baseline was recorded.

=cut

sub get_log_lines( $self, $pattern = undef )
{
	return () unless -r SYSLOG_FILE;

	my @lines;
	open my $fh, '<', SYSLOG_FILE or return ();

	my $line_num = 0;
	while (<$fh>) {
		$line_num++;
		next if $line_num <= $self->{log_baseline};
		next unless /openhapd/;
		next if defined $pattern && !/$pattern/;
		push @lines, $_;
	}
	close $fh;

	return @lines;
}

=head2 get_mqtt

    my $mqtt = $env->get_mqtt;

Get MQTT client connection. Creates connection on first call.

=cut

sub get_mqtt($self)
{
	return $self->{mqtt} if defined $self->{mqtt};

	# Require Net::MQTT::Simple
	eval { require Net::MQTT::Simple; };
	return if $@;

	# Ensure broker is running
	return unless $self->ensure_mqtt_running;

	# Create connection
	eval {
		$self->{mqtt} = Net::MQTT::Simple->new(
			"$self->{mqtt_host}:$self->{mqtt_port}");
	};

	return $self->{mqtt};
}

# Internal methods

sub _verify_system($self)
{
	# Check required binaries
	return unless -x '/usr/sbin/rcctl';
	return unless -x '/usr/local/bin/openhapd';
	return unless -x '/usr/local/bin/hapctl';

	# Check configuration exists
	return unless -f $self->{config_file};
	return unless -r $self->{config_file};

	# Check system user exists
	return unless system('id _openhap >/dev/null 2>&1') == 0;

	# Check data directory exists
	return unless -d '/var/db/openhapd';

	return 1;
}

sub _parse_config($self)
{
	open my $fh, '<', $self->{config_file} or return;

	my %config;
	my @device_topics;
	my $in_device = 0;

	while (<$fh>) {

		# Skip comments and empty lines
		next if /^\s*#/ || /^\s*$/;

		# Simple key = value
		if (/^\s*(\w+)\s*=\s*(.+)/) {
			my ( $key, $value ) = ( $1, $2 );
			$value =~ s/^"(.*)"$/$1/;    # Remove quotes
			$config{$key} = $value;

			# Update hap_port if configured
			$self->{hap_port} = $value if $key eq 'hap_port';
		}

		# Device blocks
		if (/^\s*device\s+/) {
			$in_device = 1;
		}
		elsif ( $in_device && /^\s*topic\s*=\s*(\S+)/ ) {
			push @device_topics, $1;
		}
		elsif (/^\s*\}/) {
			$in_device = 0;
		}
	}
	close $fh;

	$self->{config}        = \%config;
	$self->{device_topics} = \@device_topics;

	return 1;
}

sub _count_log_lines($self)
{
	return 0 unless -r SYSLOG_FILE;

	my $count = 0;
	if ( open my $fh, '<', SYSLOG_FILE ) {
		while (<$fh>) {
			$count++ if /openhapd/;
		}
		close $fh;
	}

	return $count;
}

1;

=head1 AUTHOR

Dick Olsson <hi@ekkis.net>

=cut

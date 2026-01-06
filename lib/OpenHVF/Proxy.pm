# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2024 Author Name <email@example.org>
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

package OpenHVF::Proxy;

use POSIX qw(setsid);
use IO::Socket::INET;
use Time::HiRes qw(usleep);

use FuguLib::Process;
use OpenHVF::Proxy::Cache;

# $class->run_child($port, $cache_dir):
#	Entry point for spawned child process
#	Sets up cache and runs the proxy server
sub run_child( $class, $port, $cache_dir )
{
	my $cache = OpenHVF::Proxy::Cache->new($cache_dir);
	my $self  = bless { cache => $cache, }, $class;
	$self->_run_proxy($port);
}

use constant {
	PORT_RANGE_START => 8080,
	PORT_RANGE_END   => 8180,
	CONNECT_TIMEOUT  => 30,
	HOST_GATEWAY     => '10.0.2.2',    # QEMU user-mode networking gateway
};

sub new( $class, $state, $cache_dir )
{
	my $self = bless {
		state     => $state,
		cache_dir => $cache_dir,
		cache     => OpenHVF::Proxy::Cache->new($cache_dir),
	}, $class;

	return $self;
}

# $self->start:
#	Start the proxy server
#	Returns port number on success, undef on failure
sub start($self)
{
	# Check if already running
	if ( $self->is_running ) {
		return $self->{state}->get_proxy_port;
	}

	my $port = $self->_find_available_port;
	if ( !defined $port ) {
		warn "No available ports in range "
		    . PORT_RANGE_START . "-"
		    . PORT_RANGE_END . "\n";
		return;
	}

	# Spawn proxy using FuguLib::Process
	my $log       = $self->{state}->vm_state_dir . "/proxy.log";
	my $cache_dir = $self->{cache_dir};
	my $result    = FuguLib::Process->spawn_perl(
		code => 'use OpenHVF::Proxy; OpenHVF::Proxy->run_child(@ARGV)',
		args => [ $port, $cache_dir ],
		daemonize   => 1,
		stdout      => $log,
		stderr      => $log,
		check_alive => 1,
		on_success  => sub($pid) {

			# Record state in callback
			$self->{state}->set_proxy_pid($pid);
			$self->{state}->set_proxy_port($port);
		},
		on_error => sub($err) {
			warn "Proxy failed to start: $err\n";
		},
	);

	return unless $result->{success};

	# Wait for proxy to be ready
	if ( !$self->wait_ready(CONNECT_TIMEOUT) ) {
		warn "Proxy failed to become ready\n";
		$self->stop;
		return;
	}

	return $port;
}

# $self->stop:
#	Stop the proxy server gracefully
sub stop($self)
{
	my $pid = $self->{state}->get_proxy_pid;
	return 1 if !defined $pid;

	# Send SIGTERM
	if ( kill( 0, $pid ) ) {
		kill( 'TERM', $pid );

		# Wait for exit
		my $waited = 0;
		while ( $waited < 5 && kill( 0, $pid ) ) {
			sleep 1;
			$waited++;
		}

		# Force kill if needed
		if ( kill( 0, $pid ) ) {
			kill( 'KILL', $pid );
			sleep 1;
		}
	}

	$self->{state}->clear_proxy_pid;
	$self->{state}->clear_proxy_port;

	return 1;
}

# $self->is_running:
#	Check if proxy is running
sub is_running($self)
{
	return $self->{state}->is_proxy_running;
}

# $self->port:
#	Get current proxy port
sub port($self)
{
	return $self->{state}->get_proxy_port;
}

# $self->guest_url:
#	Get proxy URL for use from VM guest (via QEMU gateway)
sub guest_url($self)
{
	my $port = $self->port;
	return if !defined $port;

	return "http://" . HOST_GATEWAY . ":$port";
}

# $self->host_url:
#	Get proxy URL for use from host (localhost)
sub host_url($self)
{
	my $port = $self->port;
	return if !defined $port;

	return "http://127.0.0.1:$port";
}

# $self->wait_ready($timeout):
#	Wait for proxy to accept connections
sub wait_ready( $self, $timeout = CONNECT_TIMEOUT )
{
	my $port = $self->{state}->get_proxy_port;
	return 0 if !defined $port;

	my $start = time;
	while ( time - $start < $timeout ) {
		my $sock = IO::Socket::INET->new(
			PeerAddr => '127.0.0.1',
			PeerPort => $port,
			Proto    => 'tcp',
			Timeout  => 1,
		);
		if ($sock) {
			close $sock;
			return 1;
		}
		usleep(500_000);    # 0.5 seconds
	}

	return 0;
}

# $self->cache:
#	Get the cache object
sub cache($self)
{
	return $self->{cache};
}

sub _find_available_port($self)
{
	for my $port ( PORT_RANGE_START .. PORT_RANGE_END ) {
		my $sock = IO::Socket::INET->new(
			LocalPort => $port,
			Proto     => 'tcp',
			ReuseAddr => 1,
			Listen    => 1,
		);
		if ($sock) {
			close $sock;
			return $port;
		}
	}

	return;
}

# $self->_run_proxy($port):
#	Run the proxy server (called in child process)
sub _run_proxy( $self, $port )
{
	require HTTP::Daemon;
	require LWP::UserAgent;
	require HTTP::Response;
	require IO::Select;

	# Ignore SIGPIPE - clients may disconnect mid-transfer
	local $SIG{PIPE} = 'IGNORE';

	my $daemon = HTTP::Daemon->new(
		LocalAddr => '0.0.0.0',
		LocalPort => $port,
		ReuseAddr => 1,
		Listen    => 20,
	) or die "Cannot create daemon: $!";

	# Self-pipe trick for reliable signal handling
	pipe( my $sig_read, my $sig_write ) or die "pipe: $!";
	$sig_read->blocking(0);
	$sig_write->blocking(0);

	# Use IO::Select to wait on both daemon and signal pipe
	my $select = IO::Select->new( $daemon, $sig_read );

	# Handle SIGTERM gracefully by writing to self-pipe
	my $running = 1;
	local $SIG{TERM} = sub {
		$running = 0;
		syswrite $sig_write, "x", 1;
	};

	while ($running) {

		# Wait for either client connection or signal
		my @ready = $select->can_read;
		last if !$running;

		for my $fh (@ready) {

			# Drain signal pipe if signaled
			if ( $fh == $sig_read ) {
				my $buf;
				sysread $sig_read, $buf, 100;
				next;
			}

			my $client = $daemon->accept;
			next if !$client;

			$self->_handle_client($client);
			$client->close;
		}
	}

	close $sig_read;
	close $sig_write;
	$daemon->close;
}

sub _handle_client( $self, $client )
{
	while ( my $request = $client->get_request ) {
		my $response = $self->_process_request($request);
		$client->send_response($response);
	}
}

sub _process_request( $self, $request )
{
	require HTTP::Response;
	require LWP::UserAgent;

	my $method = $request->method;
	my $url    = $request->uri->as_string;

	# Only handle GET and HEAD for caching
	if ( $method ne 'GET' && $method ne 'HEAD' ) {
		return $self->_forward_request($request);
	}

	# Check cache first
	my $cached = $self->{cache}->lookup($url);
	if ( defined $cached ) {
		return $self->_serve_cached( $cached, $request );
	}

	# Fetch from upstream
	my $response = $self->_forward_request($request);

	# Cache if appropriate
	if (       $response->is_success
		&& $self->{cache}->is_cacheable( $url, $response->code ) )
	{
		$self->{cache}->store( $url, $response->content );
	}

	return $response;
}

sub _forward_request( $self, $request )
{
	require LWP::UserAgent;

	my $ua = LWP::UserAgent->new(
		timeout => 300,
		agent   => 'OpenHVF-Proxy/1.0',
	);

	# Clone request for forwarding
	my $url = $request->uri->as_string;
	my $forwarded =
	    HTTP::Request->new( $request->method, $url,
		$request->headers->clone,
	    );

	if ( $request->content ) {
		$forwarded->content( $request->content );
	}

	my $response = $ua->request($forwarded);
	return $response;
}

sub _serve_cached( $self, $path, $request )
{
	require HTTP::Response;

	open my $fh, '<', $path or do {
		return HTTP::Response->new( 500, 'Cache read error' );
	};
	binmode $fh;
	local $/;
	my $content = <$fh>;
	close $fh;

	my $response = HTTP::Response->new( 200, 'OK' );
	$response->header( 'Content-Length' => length($content) );
	$response->header( 'X-Cache'        => 'HIT' );

	# Guess content type from URL
	my $url = $request->uri->as_string;
	if ( $url =~ /\.tgz$/ ) {
		$response->header( 'Content-Type' => 'application/x-gzip' );
	}
	elsif ( $url =~ /\.img$/ ) {
		$response->header(
			'Content-Type' => 'application/octet-stream' );
	}
	else {
		$response->header(
			'Content-Type' => 'application/octet-stream' );
	}

	# Only include content for GET requests
	if ( $request->method eq 'GET' ) {
		$response->content($content);
	}

	return $response;
}

1;

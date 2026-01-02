# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2025 OpenHAP Contributors
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

package OpenHAP::MDNS;

use POSIX;
use OpenHAP::Log qw(:all);

# OpenHAP::MDNS - mDNS service registration wrapper for mdnsctl(8)
#
# This module wraps OpenBSD's mdnsctl(8) command to register HAP services
# with mdnsd(8) for Bonjour/mDNS service discovery.

sub new( $class, %args )
{
	my $self = bless {
		service_name => $args{service_name} // 'OpenHAP Bridge',
		port         => $args{port}         // 51827,
		txt_records  => $args{txt_records}  // {},
		registered   => 0,
		mdnsctl      => $args{mdnsctl} // scalar _find_mdnsctl(),
		pid          => undef,
	}, $class;

	return $self;
}

# _find_mdnsctl():
#	Locate mdnsctl binary in common paths
#	Returns path to mdnsctl or undef if not found
sub _find_mdnsctl()
{
	my @paths = qw(
	    /usr/local/bin/mdnsctl
	    /usr/sbin/mdnsctl
	    /usr/bin/mdnsctl
	);

	for my $path (@paths) {
		return $path if -x $path;
	}

	return;
}

# $self->register_service():
#	Register the HAP service with mdnsd via mdnsctl
#	Forks a background process to keep the service registered
#	Returns 1 on success, undef on failure (logs warning)
sub register_service($self)
{
	return if $self->{registered};

	if ( !defined $self->{mdnsctl} ) {
		log_warning(
'mdnsctl not found - mDNS service registration unavailable'
		);
		return;
	}

# Build the mdnsctl command
# Format: mdnsctl publish "Service Name" hap tcp port "key1=value1,key2=value2"
# Note: mdnsctl adds the _ prefix internally to form _hap._tcp.local

	# Combine TXT records into single comma-separated string
	my $txt_string = join( ',',
		map { "$_=$self->{txt_records}{$_}" }
		sort keys %{ $self->{txt_records} } );

	my @cmd = (
		$self->{mdnsctl}, 'publish',
		$self->{service_name}, 'hap', 'tcp', $self->{port},
		$txt_string,
	);

	log_debug( 'Registering mDNS service: %s', join( ' ', @cmd ) );

	# Fork mdnsctl process to keep service registered
	# mdnsctl publish runs in an infinite loop and must stay running
	my $pid = fork;
	unless ( defined $pid ) {
		log_warning( 'Cannot fork mdnsctl process: %s', $! );
		return;
	}

	if ( $pid == 0 ) {

		# Child process
		$DB::inhibit_exit = 0;

		# Detach from parent process to run as daemon
		POSIX::setsid() or exit 1;

		# Redirect output to /dev/null
		open STDOUT, '>', '/dev/null' or exit 1;
		open STDERR, '>', '/dev/null' or exit 1;

		# Execute mdnsctl - runs indefinitely to maintain registration
		exec @cmd or exit 1;
	}

	# Parent process - store PID and mark as registered
	# Do NOT waitpid - child must continue running
	$self->{pid}        = $pid;
	$self->{registered} = 1;

	log_info( 'Registered mDNS service: %s._hap._tcp port %d (PID %d)',
		$self->{service_name}, $self->{port}, $pid );

	return 1;
}

# $self->unregister_service():
#	Unregister the HAP service by terminating the mdnsctl process
#	Returns 1 on success
sub unregister_service($self)
{
	return if !$self->{registered};

	if ( defined $self->{pid} ) {

		# Kill the mdnsctl process
		kill 'TERM', $self->{pid};

		# Reap the child process
		waitpid( $self->{pid}, 0 );

		log_info(
'Unregistered mDNS service: %s._hap._tcp (terminated PID %d)',
			$self->{service_name}, $self->{pid} );

		$self->{pid} = undef;
	}

	$self->{registered} = 0;

	return 1;
}

# $self->is_registered():
#	Check if service is currently registered
sub is_registered($self)
{
	return $self->{registered};
}

# DESTROY():
#	Clean up mdnsctl process when object is destroyed
sub DESTROY($self)
{
	$self->unregister_service() if $self->{registered};
	return;
}

1;

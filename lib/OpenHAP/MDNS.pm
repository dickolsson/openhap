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
		mdnsctl      => $args{mdnsctl} // '/usr/sbin/mdnsctl',
	}, $class;

	return $self;
}

# $self->register_service():
#	Register the HAP service with mdnsd via mdnsctl
#	Returns 1 on success, undef on failure (logs warning)
sub register_service($self)
{
	return if $self->{registered};

       # Build the mdnsctl command
       # Format: mdnsctl proxy add _hap._tcp "Service Name" port "key=value" ...
	my @cmd = (
		$self->{mdnsctl}, 'proxy',               'add',
		'_hap._tcp',      $self->{service_name}, $self->{port},
	);

	# Add TXT records
	for my $key ( sort keys %{ $self->{txt_records} } ) {
		my $value = $self->{txt_records}{$key};
		push @cmd, "$key=$value";
	}

	log_debug( 'Registering mDNS service: %s', join( ' ', @cmd ) );

	# Execute mdnsctl
	my $output  = '';
	my $success = eval {
		open my $fh, '-|', @cmd or do {
			log_warning(
'Cannot open pipe to mdnsctl for registration: %s',
				$!
			);
			return;
		};
		$output = do { local $/; <$fh> };
		close $fh;
		return $? == 0;
	};

	if ($@) {
		log_warning( 'Exception during mDNS registration: %s', $@ );
		return;
	}

	if ( !$success ) {
		log_warning( 'Failed to register mDNS service: %s',
			$output || 'command failed' );
		return;
	}

	$self->{registered} = 1;
	log_info( 'Registered mDNS service: %s._hap._tcp port %d',
		$self->{service_name}, $self->{port} );

	return 1;
}

# $self->unregister_service():
#	Unregister the HAP service from mdnsd
#	Returns 1 on success, undef on failure (logs warning)
sub unregister_service($self)
{
	return if !$self->{registered};

	# Build the mdnsctl command
	# Format: mdnsctl proxy del _hap._tcp "Service Name"
	my @cmd = (
		$self->{mdnsctl}, 'proxy', 'del',
		'_hap._tcp',      $self->{service_name},
	);

	log_debug( 'Unregistering mDNS service: %s', join( ' ', @cmd ) );

	# Execute mdnsctl
	my $output  = '';
	my $success = eval {
		open my $fh, '-|', @cmd or do {
			log_warning(
'Cannot open pipe to mdnsctl for unregistration: %s',
				$!
			);
			return;
		};
		$output = do { local $/; <$fh> };
		close $fh;
		return $? == 0;
	};

	if ($@) {
		log_warning( 'Exception during mDNS unregistration: %s', $@ );
		return;
	}

	if ( !$success ) {
		log_warning( 'Failed to unregister mDNS service: %s',
			$output || 'command failed' );
		return;
	}

	$self->{registered} = 0;
	log_info( 'Unregistered mDNS service: %s._hap._tcp',
		$self->{service_name} );

	return 1;
}

# $self->is_registered():
#	Check if service is currently registered
sub is_registered($self)
{
	return $self->{registered};
}

1;

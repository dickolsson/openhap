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

package OpenHVF::Image;

# OpenHVF::Image - Read-only access to proxy-cached OpenBSD images
#
# This module provides a simple interface to find and list OpenBSD
# miniroot images cached by the proxy. It does not download files -
# all caching is handled by the Proxy module.

use constant {
	CDN_HOST => 'cdn.openbsd.org',
	ARCH     => 'arm64',
};

sub new( $class, $cache_dir )
{
	# Expand ~ in path
	$cache_dir =~ s/^~/$ENV{HOME}/;

	my $self = bless { cache_dir => $cache_dir, }, $class;

	return $self;
}

# $self->path($version):
#	Return path to cached miniroot image for given version
#	Returns undef if not cached
sub path( $self, $version )
{
	my $path = $self->_image_path($version);
	return -f $path ? $path : undef;
}

# $self->url($version):
#	Return the CDN URL for a miniroot image
sub url( $self, $version )
{
	my $filename = $self->_image_filename($version);
	return
	      "https://"
	    . CDN_HOST
	    . "/pub/OpenBSD/$version/"
	    . ARCH
	    . "/$filename";
}

# $self->list:
#	List all cached miniroot images
#	Returns arrayref of { version, filename, path }
sub list($self)
{
	my @images;
	my $base_path = $self->_proxy_cache_path;

	return \@images if !-d $base_path;

	# Scan for version directories
	opendir my $dh, $base_path or return \@images;
	while ( my $version = readdir $dh ) {
		next if $version =~ /^\./;
		next if !-d "$base_path/$version";

		my $arch_path = "$base_path/$version/" . ARCH;
		next if !-d $arch_path;

		# Look for miniroot images
		opendir my $arch_dh, $arch_path or next;
		while ( my $file = readdir $arch_dh ) {
			if ( $file =~ /^miniroot(\d+)\.img$/ ) {
				push @images,
				    {
					version  => $version,
					filename => $file,
					path     => "$arch_path/$file",
				    };
			}
		}
		closedir $arch_dh;
	}
	closedir $dh;

	# Sort by version descending
	@images = sort { $b->{version} cmp $a->{version} } @images;

	return \@images;
}

# $self->_image_filename($version):
#	Generate miniroot filename for version (e.g., "miniroot78.img")
sub _image_filename( $self, $version )
{
	( my $ver = $version ) =~ s/\.//g;
	return "miniroot$ver.img";
}

# $self->_image_path($version):
#	Return expected cache path for miniroot image
sub _image_path( $self, $version )
{
	my $filename = $self->_image_filename($version);
	return $self->_proxy_cache_path . "/$version/" . ARCH . "/$filename";
}

# $self->_proxy_cache_path:
#	Return base path for proxy-cached OpenBSD files
sub _proxy_cache_path($self)
{
	return "$self->{cache_dir}/proxy/" . CDN_HOST . "/pub/OpenBSD";
}

1;

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

use File::Path qw(make_path);
use Digest::SHA;

use constant {
	BASE_URL => 'https://cdn.openbsd.org/pub/OpenBSD',
	ARCH     => 'arm64',
};

sub new( $class, $cache_dir )
{
	# Expand ~ in path
	$cache_dir =~ s/^~/$ENV{HOME}/;

	my $self = bless { cache_dir => $cache_dir, }, $class;

	$self->_ensure_cache_dir;
	return $self;
}

sub _ensure_cache_dir($self)
{
	if ( !-d $self->{cache_dir} ) {
		make_path( $self->{cache_dir} );
	}
}

sub download( $self, $version )
{
	my $cache_file = $self->_cache_filename($version);
	my $path       = "$self->{cache_dir}/$cache_file";

	# Return cached path if exists and verified
	if ( -f $path && $self->verify($version) ) {
		return $path;
	}

	# Fetch checksum first
	my $expected_sha = $self->_fetch_checksum($version);
	if ( !defined $expected_sha ) {
		warn "Failed to fetch checksum for $version " . ARCH . "\n";
		return;
	}

	# Download image
	my $url    = $self->_image_url($version);
	my $result = $self->_download_file( $url, $path );

	if ( !$result ) {
		warn "Failed to download $url\n";
		return;
	}

	# Verify download
	if ( !$self->verify($version) ) {
		warn "Checksum verification failed for $cache_file\n";
		unlink $path;
		return;
	}

	return $path;
}

sub verify( $self, $version )
{
	my $cache_file = $self->_cache_filename($version);
	my $path       = "$self->{cache_dir}/$cache_file";

	return 0 if !-f $path;

	my $expected = $self->_fetch_checksum($version);
	return 0 if !defined $expected;

	my $actual = $self->_calculate_sha256($path);
	return $expected eq $actual;
}

sub path( $self, $version )
{
	my $cache_file = $self->_cache_filename($version);
	my $path       = "$self->{cache_dir}/$cache_file";
	return -f $path ? $path : undef;
}

sub list($self)
{
	my @images;

	opendir my $dh, $self->{cache_dir} or return \@images;
	while ( my $file = readdir $dh ) {
		next if $file =~ /^\./;
		next if $file =~ /^SHA256/;

		if ( $file =~ /^miniroot(\d+)\.img$/ ) {
			my $ver = $1;

			# Convert version: 78 -> 7.8
			$ver =~ s/(\d)(\d)/$1.$2/;
			push @images,
			    {
				version  => $ver,
				filename => $file,
				path     => "$self->{cache_dir}/$file",
			    };
		}
	}
	closedir $dh;

	return \@images;
}

sub remove( $self, $version )
{
	my $cache_file = $self->_cache_filename($version);
	my $path       = "$self->{cache_dir}/$cache_file";

	if ( -f $path ) {
		unlink $path or do {
			warn "Cannot remove $path: $!";
			return 0;
		};
	}

	# Also remove cached checksum
	my $sha_file = "$self->{cache_dir}/SHA256-$version";
	unlink $sha_file if -f $sha_file;

	return 1;
}

sub _image_filename( $self, $version )
{
	# Convert version: 7.8 -> 78
	# Note: OpenBSD uses same miniroot filename for all archs
	( my $ver = $version ) =~ s/\.//g;
	return "miniroot$ver.img";
}

# Simpler cache filename (no arch suffix needed)
sub _cache_filename( $self, $version )
{
	( my $ver = $version ) =~ s/\.//g;
	return "miniroot$ver.img";
}

sub _image_url( $self, $version )
{
	my $filename = $self->_image_filename($version);
	return BASE_URL . "/$version/" . ARCH . "/$filename";
}

sub _fetch_checksum( $self, $version )
{
	my $sha_file = "$self->{cache_dir}/SHA256-$version";

	# Use cached checksum if available
	if ( -f $sha_file ) {
		open my $fh, '<', $sha_file or return;
		my $sha = <$fh>;
		close $fh;
		chomp $sha;
		return $sha if $sha =~ /^[a-f0-9]{64}$/i;
	}

	# Fetch SHA256 file from OpenBSD
	my $url     = BASE_URL . "/$version/" . ARCH . "/SHA256";
	my $content = $self->_fetch_url($url);
	return if !defined $content;

	# Parse SHA256 file to find our image
	my $filename = $self->_image_filename($version);
	for my $line ( split /\n/, $content ) {
		if ( $line =~ /SHA256\s*\(([^)]+)\)\s*=\s*([a-f0-9]{64})/i ) {
			my ( $file, $sha ) = ( $1, $2 );
			if ( $file eq $filename ) {

				# Cache the checksum
				open my $fh, '>', $sha_file;
				print $fh "$sha\n" if $fh;
				close $fh          if $fh;
				return $sha;
			}
		}
	}

	return;
}

sub _calculate_sha256( $self, $path )
{
	open my $fh, '<:raw', $path or return;
	my $sha = Digest::SHA->new(256);
	$sha->addfile($fh);
	close $fh;
	return $sha->hexdigest;
}

sub _fetch_url( $self, $url )
{
	# Use list form of open to prevent shell injection
	open my $fh, '-|', 'curl', '-fsSL', '--', $url
	    or return;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $? == 0 ? $content : undef;
}

sub _download_file( $self, $url, $path )
{
	# Use curl with progress
	my $result = system( 'curl', '-fL', '-o', $path, $url );
	return $result == 0;
}

1;

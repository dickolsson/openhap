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

package OpenHVF::Disk;

use File::Path qw(make_path);
use File::Basename;

sub new ( $class, $state_dir )
{
	my $self = bless { state_dir => $state_dir, }, $class;

	return $self;
}

sub create ( $self, $name, $size, $backing_image = undef )
{
	my $path = $self->path($name);
	my $dir  = dirname($path);

	make_path($dir) if !-d $dir;

	return $path if -f $path;    # Already exists

	my @cmd = ( 'qemu-img', 'create', '-f', 'qcow2' );

	if ( defined $backing_image ) {
		push @cmd, '-b', $backing_image, '-F', 'raw';
	}

	push @cmd, $path, $size;

	my $result = system(@cmd);
	if ( $result != 0 ) {
		warn "Failed to create disk image: $path\n";
		return;
	}

	return $path;
}

sub disk_exists ( $self, $name )
{
	return -f $self->path($name);
}

sub path ( $self, $name )
{
	return "$self->{state_dir}/$name/disk.qcow2";
}

sub remove ( $self, $name )
{
	my $path = $self->path($name);
	if ( -f $path ) {
		unlink $path or do {
			warn "Cannot remove $path: $!";
			return 0;
		};
	}
	return 1;
}

sub info ( $self, $name )
{
	my $path = $self->path($name);
	return if !-f $path;

	my $output = `qemu-img info --output=json "$path" 2>/dev/null`;
	return if $? != 0;

	require JSON::XS;
	return eval { JSON::XS::decode_json($output) };
}

1;

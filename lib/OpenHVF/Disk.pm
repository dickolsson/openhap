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

# Suppress qemu-img's verbose "Formatting..." output by redirecting to /dev/null
# We use shell redirection since system() doesn't provide output control
	my $cmd_str =
	    join( ' ', map { my $s = $_; $s =~ s/'/'\\''/g; "'$s'" } @cmd );
	my $result = system("$cmd_str >/dev/null 2>&1");

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

# P5: Check disk image integrity
# Returns hashref with 'status' ('ok' or 'corrupted') and 'output'
sub check ( $self, $name )
{
	my $path = $self->path($name);
	return if !-f $path;

	my $output    = `qemu-img check "$path" 2>&1`;
	my $exit_code = $?;

	if ( $exit_code != 0 ) {
		return {
			status => 'corrupted',
			output => $output,
			path   => $path,
		};
	}

	return {
		status => 'ok',
		output => $output,
		path   => $path,
	};
}

# P5: Repair disk image
# Returns true on success, false on failure
sub repair ( $self, $name )
{
	my $path = $self->path($name);
	return 0 if !-f $path;

	# Run qemu-img check with repair option
	my $result = system( 'qemu-img', 'check', '-r', 'all', $path );
	return $result == 0;
}

1;

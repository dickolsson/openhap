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

package OpenHVF::State;

use File::Path     qw(make_path);
use File::Temp     qw(tempfile);
use File::Basename qw(dirname);
use JSON::XS;
use FuguLib::State;
use IO::Handle;

use constant { MAX_VM_NAME_LENGTH => 255, };

sub new( $class, $state_dir, $vm_name )
{
	# Validate VM name length
	if ( length($vm_name) > MAX_VM_NAME_LENGTH ) {
		warn "VM name too long (max "
		    . MAX_VM_NAME_LENGTH
		    . " characters)\n";
		return;
	}

	# Validate VM name characters (no path separators or null bytes)
	if ( $vm_name =~ m{[/\x00]} ) {
		warn "VM name contains invalid characters\n";
		return;
	}

	my $vm_state_dir = "$state_dir/$vm_name";

	my $self = bless {
		state_dir      => $state_dir,
		vm_name        => $vm_name,
		vm_state_dir   => $vm_state_dir,
		vm_pid_file    => "$vm_state_dir/vm.pid",
		proxy_pid_file => "$vm_state_dir/proxy.pid",
		status_file    => "$vm_state_dir/status",
		disk_path      => "$vm_state_dir/disk.qcow2",
		_vm_state      => undef,
		_proxy_state   => undef,
	}, $class;

	if ( !$self->_ensure_dir ) {
		return;
	}

	# Initialize FuguLib::State objects for PID management
	$self->{_vm_state}    = FuguLib::State->new( $self->{vm_pid_file} );
	$self->{_proxy_state} = FuguLib::State->new( $self->{proxy_pid_file} );

	$self->load;

	return $self;
}

sub _ensure_dir($self)
{
	my $dir = $self->{vm_state_dir};

	# Check for symlinks (refuse to follow for security)
	if ( -l $dir ) {
		warn "State directory is a symlink: $dir\n";
		return 0;
	}

	# Check if path exists but is not a directory
	if ( -e $dir && !-d $dir ) {
		warn "State path exists but is not a directory: $dir\n";
		return 0;
	}

	if ( !-d $dir ) {
		eval { make_path($dir) };
		if ($@) {

			# Extract the error message without exposing internals
			my $err = $@;
			$err =~ s/ at \S+ line \d+.*//s;
			warn "Cannot create state directory: $err\n";
			return 0;
		}
	}
	return 1;
}

sub load($self)
{
	if ( -f $self->{status_file} ) {
		open my $fh, '<', $self->{status_file} or return;
		local $/;
		my $json = <$fh>;
		close $fh;

		eval { $self->{data} = decode_json($json); };
		if ($@) {
			warn "State file corrupted: $self->{status_file}: $@";
			$self->{data} = {};
		}
	}
	else {
		$self->{data} = {};
	}

	return $self;
}

sub save($self)
{
	my $dir = dirname( $self->{status_file} );

	# P4: Write to temp file then atomically rename
	my ( $fh, $tmpfile ) = tempfile(
		DIR    => $dir,
		UNLINK => 0,
	);

	if ( !$fh ) {
		warn "Cannot create temp file in $dir: $!";
		return;
	}

	print $fh encode_json( $self->{data} );

	# Ensure data is on disk before rename
	$fh->flush;
	$fh->sync;
	close $fh;

	# Atomic rename
	rename( $tmpfile, $self->{status_file} ) or do {
		unlink $tmpfile;
		warn "Cannot save state: $!";
		return;
	};

	# Sync directory for durability
	$self->_sync_directory($dir);

	return $self;
}

sub _sync_directory( $self, $dir )
{
	if ( open my $dh, '<', $dir ) {
		$dh->sync;
		close $dh;
	}
}

# VM PID management (using FuguLib::State)
sub set_vm_pid( $self, $pid )
{
	return unless $self->{_vm_state}->write_pid($pid);
	return $self;
}

sub get_vm_pid($self)
{
	return $self->{_vm_state}->read_pid();
}

sub clear_vm_pid($self)
{
	unlink $self->{vm_pid_file};
	return $self;
}

sub is_vm_running($self)
{
	return $self->{_vm_state}->is_running() ? 1 : 0;
}

# Proxy PID management (using FuguLib::State)
sub set_proxy_pid( $self, $pid )
{
	return unless $self->{_proxy_state}->write_pid($pid);
	return $self;
}

sub get_proxy_pid($self)
{
	return $self->{_proxy_state}->read_pid();
}

sub clear_proxy_pid($self)
{
	unlink $self->{proxy_pid_file};
	return $self;
}

sub is_proxy_running($self)
{
	my $pid = $self->get_proxy_pid;
	return 0 if !defined $pid;

	# Check if process is alive
	return kill( 0, $pid ) ? 1 : 0;
}

# Proxy port management
sub set_proxy_port( $self, $port )
{
	$self->{data}{proxy_port} = $port;
	$self->save;
	return $self;
}

sub get_proxy_port($self)
{
	return $self->{data}{proxy_port};
}

sub clear_proxy_port($self)
{
	delete $self->{data}{proxy_port};
	$self->save;
	return $self;
}

# Disk state
sub disk_path($self)
{
	return $self->{disk_path};
}

sub disk_exists($self)
{
	return -f $self->{disk_path};
}

# Installation state
sub is_installed($self)
{
	return $self->{data}{installed} ? 1 : 0;
}

sub mark_installed($self)
{
	$self->{data}{installed}    = 1;
	$self->{data}{installed_at} = time;
	$self->save;
	return $self;
}

# Root password management (stored securely in state for initial setup)
sub set_root_password( $self, $password )
{
	$self->{data}{root_password} = $password;
	$self->save;
	return $self;
}

sub get_root_password($self)
{
	return $self->{data}{root_password};
}

# SSH key installation state
# Stores the actual pubkey that was installed
sub get_installed_ssh_pubkey($self)
{
	return $self->{data}{ssh_pubkey_installed};
}

sub set_installed_ssh_pubkey( $self, $pubkey )
{
	$self->{data}{ssh_pubkey_installed}    = $pubkey;
	$self->{data}{ssh_pubkey_installed_at} = time;
	$self->save;
	return $self;
}

sub vm_state_dir($self)
{
	return $self->{vm_state_dir};
}

# P5/P7: Shutdown state tracking
# Tracks whether VM was shutdown cleanly to detect filesystem corruption risk

sub mark_clean_shutdown($self)
{
	$self->{data}{shutdown_clean} = 1;
	$self->{data}{shutdown_at}    = time;
	delete $self->{data}{running};
	$self->save;
	return $self;
}

sub mark_unclean_shutdown($self)
{
	$self->{data}{shutdown_clean} = 0;
	$self->{data}{shutdown_at}    = time;
	delete $self->{data}{running};
	$self->save;
	return $self;
}

sub mark_running($self)
{
	$self->{data}{running}    = 1;
	$self->{data}{started_at} = time;
	delete $self->{data}{shutdown_clean};
	$self->save;
	return $self;
}

sub was_unclean_shutdown($self)
{
	# If explicitly marked as unclean
	if ( exists $self->{data}{shutdown_clean}
		&& !$self->{data}{shutdown_clean} )
	{
		return 1;
	}

	# If marked running but VM process is dead = crashed/killed
	if ( $self->{data}{running} && !$self->is_vm_running ) {
		return 1;
	}

	return 0;
}

sub clear_shutdown_state($self)
{
	delete $self->{data}{shutdown_clean};
	delete $self->{data}{running};
	$self->save;
	return $self;
}

sub data($self)
{
	return $self->{data};
}

1;

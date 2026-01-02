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

# OpenHVF::VM - OpenBSD VM management for macOS/arm64
#
# Opinionated VM controller for running OpenBSD guests on Apple Silicon.
# Uses QMP for reliable VM lifecycle management.

package OpenHVF::VM;

use File::Path  qw(make_path);
use POSIX       qw(setsid);
use Time::HiRes qw(usleep);

use OpenHVF::Image;
use OpenHVF::Disk;
use OpenHVF::SSH;
use OpenHVF::Expect;
use OpenHVF::Util;
use OpenHVF::QMP;

use constant {
	EXIT_SUCCESS        => 0,
	EXIT_ERROR          => 1,
	EXIT_VM_RUNNING     => 5,
	EXIT_VM_NOT_RUNNING => 6,
	EXIT_TIMEOUT        => 7,

	# Fixed configuration for OpenBSD on Apple Silicon
	QEMU_BINARY    => 'qemu-system-aarch64',
	MEMORY_DEFAULT => '1G',
	CPU_COUNT      => 2,
};

sub new( $class, %args )
{
	my $self = bless {
		config => $args{config},
		state  => $args{state},
		output => $args{output},
	}, $class;

	return $self;
}

# Idempotent: ensure VM is running
sub up($self)
{
	my $config = $self->{config};
	my $state  = $self->{state};
	my $output = $self->{output};

	# Check if already running
	if ( $self->_is_running ) {
		$output->info("VM '$config->{name}' is already running");
		return EXIT_SUCCESS;
	}

	# Ensure image is downloaded
	$output->info("Checking OpenBSD image...");
	my $cache_dir  = $self->_cache_dir;
	my $image      = OpenHVF::Image->new($cache_dir);
	my $image_path = $image->path( $config->{version} );

	if ( !defined $image_path ) {
		$output->info("Downloading OpenBSD $config->{version}...");
		$image_path = $image->download( $config->{version} );
		if ( !defined $image_path ) {
			$output->error("Failed to download image");
			return EXIT_ERROR;
		}
	}
	else {
		$output->info("Using cached image: $image_path");
	}

	# Ensure disk exists
	my $disk_path = $state->disk_path;

	if ( !$state->disk_exists ) {
		$output->info("Creating disk image ($config->{disk_size})...");
		my $disk = OpenHVF::Disk->new( $state->{state_dir} );
		my $result =
		    $disk->create( $config->{name}, $config->{disk_size} );
		if ( !defined $result ) {
			$output->error("Failed to create disk");
			return EXIT_ERROR;
		}
	}

	# Start VM
	$output->info("Starting VM...");

	# Only attach install media if not already installed
	my $boot_image = $state->is_installed ? undef : $image_path;
	my $pid        = $self->_start_qemu($boot_image);
	if ( !defined $pid ) {
		$output->error("Failed to start VM");
		return EXIT_ERROR;
	}

	$output->pid( $config->{name}, $pid );

	# Install if needed
	if ( !$state->is_installed ) {

		# Start caching proxy for installation
		require OpenHVF::Proxy;
		my $proxy      = OpenHVF::Proxy->new( $state, $cache_dir );
		my $proxy_port = $proxy->start;
		my $proxy_url;

		if ( defined $proxy_port ) {
			$proxy_url = $proxy->url;
			$output->info("Proxy started: $proxy_url");
		}
		else {
			$proxy_url = 'none';
			$output->info(
"Proxy not available, downloads will not be cached"
			);
		}

		# Generate a strong random password for this installation
		my $root_password = OpenHVF::Util->generate_password(32);
		$state->set_root_password($root_password);
		$output->info("Generated secure root password");

		$output->info("Installing OpenBSD...");
		my $expect = OpenHVF::Expect->new(
			host => 'localhost',
			port => $config->{console_port},
		);

		# Wait a moment for VM to start
		sleep 5;

		# Use the generated password for installation
		my $install_config = {
			%$config,
			root_password => $root_password,
			proxy_url     => $proxy_url,
		};
		my $ok = $expect->run_install($install_config);
		if ( !$ok ) {
			$output->error("Installation failed");
			$proxy->stop if defined $proxy_port;
			return EXIT_ERROR;
		}

		$state->mark_installed;
		$output->info("Installation complete");

		# Stop proxy after installation
		if ( defined $proxy_port ) {
			$proxy->stop;
			$output->info("Proxy stopped");
		}

		# Stop VM via QMP (graceful)
		$output->info("Stopping installation VM...");
		$self->_qmp_quit;
		sleep 2;
		$state->clear_vm_pid;

		# Restart VM without install media
		$output->info("Restarting installed system...");
		$pid = $self->_start_qemu;    # No boot image, no exit_on_halt
		if ( !defined $pid ) {
			$output->error("Failed to restart VM");
			return EXIT_ERROR;
		}
		$output->pid( $config->{name}, $pid );

		# Wait for first boot
		sleep 10;

		# Wait for SSH with password auth
		$output->info("Waiting for SSH...");
		if ( !$self->_wait_ssh_password( $root_password, 120 ) ) {
			$output->error("Timeout waiting for SSH");
			return EXIT_TIMEOUT;
		}

		# Install SSH authorized key for future key-based auth
		if ( !$self->_install_ssh_key($root_password) ) {
			$output->error("Failed to install SSH key");
			return EXIT_ERROR;
		}
		$output->info("SSH key installed");

		$output->success("VM ready");
		return EXIT_SUCCESS;
	}

	# Wait for SSH (key-based auth for already installed VMs)
	$output->info("Waiting for SSH...");
	if ( !$self->wait_ssh(120) ) {
		$output->error("Timeout waiting for SSH");
		return EXIT_TIMEOUT;
	}

	$output->success("VM ready");
	return EXIT_SUCCESS;
}

sub down($self)
{
	my $state  = $self->{state};
	my $output = $self->{output};
	my $config = $self->{config};

	# Stop proxy if running
	require OpenHVF::Proxy;
	my $proxy = OpenHVF::Proxy->new( $state, $self->_cache_dir );
	if ( $proxy->is_running ) {
		$proxy->stop;
		$output->info("Proxy stopped");
	}

	if ( !$self->_is_running ) {
		$output->info("VM '$config->{name}' is not running");
		return EXIT_SUCCESS;
	}

	$output->info("Shutting down VM...");

	# Try graceful ACPI shutdown via QMP
	if ( $self->_qmp_powerdown ) {
		if ( $self->_wait_exit(30) ) {
			$state->clear_vm_pid;
			$output->success("VM stopped");
			return EXIT_SUCCESS;
		}
	}

	# Fall back to SSH shutdown
	my $ssh = OpenHVF::SSH->new(
		host => 'localhost',
		port => $config->{ssh_port},
		user => 'root',
	);
	$ssh->run_command('shutdown -p now');

	if ( $self->_wait_exit(30) ) {
		$state->clear_vm_pid;
		$output->success("VM stopped");
		return EXIT_SUCCESS;
	}

	# Force quit via QMP
	$output->info("Force stopping VM...");
	$self->_qmp_quit;
	$state->clear_vm_pid;
	$output->success("VM stopped");

	return EXIT_SUCCESS;
}

sub destroy($self)
{
	my $state  = $self->{state};
	my $output = $self->{output};
	my $config = $self->{config};

	# Stop proxy if running
	require OpenHVF::Proxy;
	my $proxy = OpenHVF::Proxy->new( $state, $self->_cache_dir );
	if ( $proxy->is_running ) {
		$proxy->stop;
		$output->info("Proxy stopped");
	}

	# Stop if running
	if ( $self->_is_running ) {
		$self->stop(1);
	}

	# Remove disk
	my $disk_path = $state->disk_path;
	if ( -f $disk_path ) {
		$output->info("Removing disk image...");
		unlink $disk_path or do {
			$output->error("Cannot remove $disk_path: $!");
			return EXIT_ERROR;
		};
	}

	# Remove QMP socket
	my $qmp_path = $self->_qmp_socket_path;
	unlink $qmp_path if -S $qmp_path;

	# Clear state
	$state->{data} = {};
	$state->save;

	$output->success("VM '$config->{name}' destroyed");
	return EXIT_SUCCESS;
}

sub start($self)
{
	my $state  = $self->{state};
	my $output = $self->{output};
	my $config = $self->{config};

	if ( $self->_is_running ) {
		$output->error("VM '$config->{name}' is already running");
		return EXIT_VM_RUNNING;
	}

	if ( !$state->disk_exists ) {
		$output->error("No disk image. Run 'openhvf up' first.");
		return EXIT_ERROR;
	}

	my $pid = $self->_start_qemu;
	if ( !defined $pid ) {
		$output->error("Failed to start VM");
		return EXIT_ERROR;
	}

	$output->pid( $config->{name}, $pid );
	return EXIT_SUCCESS;
}

sub stop( $self, $force = 0 )
{
	my $state  = $self->{state};
	my $output = $self->{output};
	my $config = $self->{config};

	if ( !$self->_is_running ) {
		$output->info("VM '$config->{name}' is not running");
		return EXIT_SUCCESS;
	}

	if ($force) {
		$output->info("Force stopping VM...");
		$self->_qmp_quit;
		$state->clear_vm_pid;
		$output->success("VM stopped");
		return EXIT_SUCCESS;
	}

	# Try graceful shutdown with timeout
	$output->info("Shutting down VM gracefully...");
	if ( $self->_qmp_powerdown ) {
		if ( $self->_wait_exit(30) ) {
			$state->clear_vm_pid;
			$output->success("VM stopped");
			return EXIT_SUCCESS;
		}
	}

	# If graceful shutdown times out, force stop
	$output->info("Graceful shutdown timed out, force stopping...");
	$self->_qmp_quit;
	$state->clear_vm_pid;
	$output->success("VM stopped");
	return EXIT_SUCCESS;
}

sub status($self)
{
	my $state  = $self->{state};
	my $config = $self->{config};

	my $running = $self->_is_running;
	my $pid     = $state->get_vm_pid;

	# Query QEMU status via QMP if running
	my $qemu_status;
	if ($running) {
		my $qmp = $self->_qmp_connect;
		if ($qmp) {
			my $status = $qmp->query_status;
			$qemu_status = $status->{status} if $status;
			$qmp->disconnect;
		}
	}

	return {
		name  => $config->{name},
		state => $running ? ( $qemu_status // 'running' ) : 'stopped',
		pid   => $pid,
		ssh_port     => $config->{ssh_port},
		console_port => $config->{console_port},
		installed    => $state->is_installed ? 1 : 0,
		disk_exists  => $state->disk_exists  ? 1 : 0,
	};
}

sub is_running($self)
{
	return $self->_is_running;
}

sub pid($self)
{
	return $self->{state}->get_vm_pid;
}

sub ssh_port($self)
{
	return $self->{config}{ssh_port};
}

sub console_port($self)
{
	return $self->{config}{console_port};
}

# Wait operations
sub wait_ssh( $self, $timeout = 120, $sig = undef )
{
	my $config = $self->{config};

	# Uses SSH agent for authentication
	my $ssh = OpenHVF::SSH->new(
		host => 'localhost',
		port => $config->{ssh_port},
		user => 'root',
	);

	return $ssh->wait_available( $timeout, $sig );
}

# $self->_wait_ssh_password($password, $timeout):
#	Wait for SSH to become available using password authentication
#	Used during initial installation before SSH key is installed
sub _wait_ssh_password( $self, $password, $timeout = 120 )
{
	my $config = $self->{config};

	my $ssh = OpenHVF::SSH->new(
		host     => 'localhost',
		port     => $config->{ssh_port},
		user     => 'root',
		password => $password,
	);

	return $ssh->wait_available($timeout);
}

# $self->_install_ssh_key($password):
#	Install the SSH public key from config into authorized_keys
#	Uses password authentication since key is not yet installed
sub _install_ssh_key( $self, $password )
{
	my $config = $self->{config};
	my $state  = $self->{state};
	my $output = $self->{output};

	# Get SSH public key from config
	my $ssh_pubkey = $config->{ssh_pubkey};
	if ( !defined $ssh_pubkey || $ssh_pubkey eq '' ) {
		$output->error("No ssh_pubkey configured in ~/.openhvfrc");
		return 0;
	}

	# Connect with password
	my $ssh = OpenHVF::SSH->new(
		host     => 'localhost',
		port     => $config->{ssh_port},
		user     => 'root',
		password => $password,
	);

	# Create .ssh directory
	my $result =
	    $ssh->run_command('mkdir -p /root/.ssh && chmod 700 /root/.ssh');
	if ( $result->{exit_code} != 0 ) {
		return 0;
	}

	# Write authorized_keys file
	my $authkeys_content = $ssh_pubkey . "\n";
	if (
		$ssh->write_file(
			'/root/.ssh/authorized_keys', $authkeys_content,
			0600
		) != 0
	    )
	{
		return 0;
	}

	$state->mark_ssh_key_installed;
	return 1;
}

# QMP methods
sub _qmp_socket_path($self)
{
	return $self->{state}{vm_state_dir} . '/qmp.sock';
}

sub _qmp_connect($self)
{
	my $qmp = OpenHVF::QMP->new( $self->_qmp_socket_path );
	return $qmp->open_connection ? $qmp : undef;
}

sub _qmp_powerdown($self)
{
	my $qmp    = $self->_qmp_connect or return 0;
	my $result = $qmp->powerdown;
	$qmp->disconnect;
	return $result;
}

sub _qmp_quit($self)
{
	my $qmp = $self->_qmp_connect or return 0;
	return $qmp->quit;
}

sub _is_running($self)
{
	my $pid = $self->{state}->get_vm_pid;
	return 0 if !defined $pid;

	# Check if process is alive
	return 0 if !kill( 0, $pid );

	# Optionally verify via QMP (more reliable)
	my $qmp = $self->_qmp_connect;
	if ($qmp) {
		my $running = $qmp->is_running;
		$qmp->disconnect;
		return $running;
	}

	# Fall back to process check
	return 1;
}

sub _wait_exit( $self, $timeout )
{
	my $start = time;
	while ( time - $start < $timeout ) {
		my $pid = $self->{state}->get_vm_pid;
		return 1 if !defined $pid || !kill( 0, $pid );
		sleep 1;
	}
	return 0;
}

# QEMU startup
sub _start_qemu( $self, $boot_image = undef )
{
	my $config = $self->{config};
	my $state  = $self->{state};

	my @cmd = (QEMU_BINARY);

	# Machine type for arm64 with HVF acceleration
	push @cmd, '-M',     'virt,highmem=off';
	push @cmd, '-cpu',   'host';
	push @cmd, '-accel', 'hvf';

	# Memory and CPU
	push @cmd, '-m',   $config->{memory} // MEMORY_DEFAULT;
	push @cmd, '-smp', CPU_COUNT;

	# EFI firmware for arm64
	my $bios = $self->_find_efi_firmware;
	if ( defined $bios ) {
		push @cmd, '-bios', $bios;
	}

	# Main disk
	my $disk_path = $state->disk_path;
	push @cmd, '-drive', "file=$disk_path,format=qcow2,if=virtio";

	# Boot image (CD-ROM) for installation
	if ( defined $boot_image ) {
		push @cmd, '-drive',
		    "file=$boot_image,format=raw,if=virtio,readonly=on";
	}

	# Network with port forwarding
	my $ssh_port = $config->{ssh_port};
	push @cmd, '-device', 'virtio-net-pci,netdev=net0';
	push @cmd, '-netdev', "user,id=net0,hostfwd=tcp::$ssh_port-:22";

	# Serial console on telnet
	my $console_port = $config->{console_port};
	push @cmd, '-serial', "tcp::$console_port,server,telnet,nowait";

	# QMP control socket
	my $qmp_path = $self->_qmp_socket_path;
	unlink $qmp_path if -S $qmp_path;
	push @cmd, '-qmp', "unix:$qmp_path,server,nowait";

	# PID file for reliable tracking
	push @cmd, '-pidfile', $state->{vm_pid_file};

	# No graphics display (headless)
	push @cmd, '-display', 'none';

	# Spawn QEMU using FuguLib::Process
	my $log_file = "$state->{vm_state_dir}/qemu.log";
	my $result   = FuguLib::Process->spawn(
		cmd         => \@cmd,
		daemonize   => 1,
		stdout      => $log_file,
		stderr      => $log_file,
		check_alive => 0,    # Don't check, QEMU writes its own PID file
	);

	return unless $result->{success};

	# Wait for QEMU to write PID file
	my $start = time;
	while ( time - $start < 5 ) {
		if ( -f $state->{vm_pid_file} ) {
			my $qemu_pid = $state->get_vm_pid;
			return $qemu_pid
			    if defined $qemu_pid && kill( 0, $qemu_pid );
		}
		usleep(100_000);    # 0.1 seconds
	}

	# Fallback: use forked PID from FuguLib::Process
	my $pid = $result->{pid};
	if ( kill( 0, $pid ) ) {
		$state->set_vm_pid($pid);
		return $pid;
	}

	return;
}

sub _find_efi_firmware($self)
{
	my @paths = (
		'/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'/usr/local/share/qemu/edk2-aarch64-code.fd',
	);

	for my $path (@paths) {
		return $path if -f $path;
	}

	# Try glob for versioned Homebrew paths
	my @glob_paths =
	    glob('/opt/homebrew/Cellar/qemu/*/share/qemu/edk2-aarch64-code.fd');
	return $glob_paths[0] if @glob_paths;

	return;
}

sub _cache_dir($self)
{
	my $home = $ENV{HOME} // '/root';
	return "$home/.cache/openhvf";
}

1;

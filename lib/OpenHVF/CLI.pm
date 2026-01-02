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

package OpenHVF::CLI;

use Getopt::Long qw(:config require_order bundling);
use File::Basename;

use OpenHVF::Config;
use OpenHVF::State;
use OpenHVF::Output;
use OpenHVF::Image;
use OpenHVF::Disk;
use OpenHVF::VM;
use OpenHVF::SSH;
use OpenHVF::Expect;

use constant {
	EXIT_SUCCESS         => 0,
	EXIT_ERROR           => 1,
	EXIT_INVALID_ARGS    => 2,
	EXIT_CONFIG_ERROR    => 3,
	EXIT_VM_NOT_FOUND    => 4,
	EXIT_VM_RUNNING      => 5,
	EXIT_VM_NOT_RUNNING  => 6,
	EXIT_TIMEOUT         => 7,
	EXIT_SSH_FAILED      => 8,
	EXIT_EXPECT_FAILED   => 9,
	EXIT_DOWNLOAD_FAILED => 10,
};

my %commands = (
	'up'      => \&cmd_up,
	'down'    => \&cmd_down,
	'destroy' => \&cmd_destroy,
	'status'  => \&cmd_status,
	'start'   => \&cmd_start,
	'stop'    => \&cmd_stop,
	'ssh'     => \&cmd_ssh,
	'console' => \&cmd_console,
	'expect'  => \&cmd_expect,
	'wait'    => \&cmd_wait,
	'image'   => \&cmd_image,
	'init'    => \&cmd_init,
	'help'    => \&cmd_help,
);

sub new ( $class, %opts )
{
	my $self = bless {
		vm_name => $opts{vm} // 'default',
		project => $opts{project},
		quiet   => $opts{quiet} // 0,
	}, $class;

	$self->{output} = OpenHVF::Output->new( $self->{quiet} );

	return $self;
}

sub run ( $class, @argv )
{
	my %opts;
	my $parser = Getopt::Long::Parser->new;
	$parser->configure( 'require_order', 'bundling' );

	$parser->getoptionsfromarray(
		\@argv,
		'vm=s'      => \$opts{vm},
		'project=s' => \$opts{project},
		'quiet|q'   => \$opts{quiet},
		'help|h'    => \$opts{help},
	) or return EXIT_INVALID_ARGS;

	if ( $opts{help} && !@argv ) {
		return cmd_help($class);
	}

	my $command = shift @argv // 'help';

	if ( !exists $commands{$command} ) {
		warn "openhvf: unknown command: $command\n";
		return EXIT_INVALID_ARGS;
	}

	my $self = $class->new(%opts);

	# Load config if not init command
	if ( $command ne 'init' && $command ne 'help' ) {
		my $project_root = $opts{project}
		    // OpenHVF::Config->find_project_root;
		if ( !defined $project_root ) {
			$self->{output}->error(
"Not in an OpenHVF project. Run 'openhvf init' first."
			);
			return EXIT_CONFIG_ERROR;
		}

		# Validate project path exists
		if ( !-d $project_root ) {
			$self->{output}->error(
				"Project path does not exist: $project_root");
			return EXIT_CONFIG_ERROR;
		}
		$self->{config} = OpenHVF::Config->new($project_root);
		$self->{state} =
		    OpenHVF::State->new( $self->{config}->state_dir,
			$self->{vm_name}, );
		if ( !defined $self->{state} ) {
			$self->{output}->error(
"Cannot initialize state for VM '$self->{vm_name}'"
			);
			return EXIT_ERROR;
		}
	}

	return $commands{$command}->( $self, @argv );
}

sub _load_vm ($self)
{
	my $vm_config = $self->{config}->load_vm( $self->{vm_name} );
	if ( !defined $vm_config ) {
		$self->{output}->error("VM '$self->{vm_name}' not found");
		return;
	}

	return OpenHVF::VM->new(
		config => $vm_config,
		state  => $self->{state},
		output => $self->{output},
	);
}

# Idempotent: ensure VM is running
sub cmd_up ( $self, @args )
{
	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	return $vm->up;
}

# Stop VM gracefully
sub cmd_down ( $self, @args )
{
	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	return $vm->down;
}

# Stop VM and delete disk image
sub cmd_destroy ( $self, @args )
{
	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	return $vm->destroy;
}

# Show VM status
sub cmd_status ( $self, @args )
{
	my $vm     = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	my $status = $vm->status;
	$self->{output}->data($status);
	return EXIT_SUCCESS;
}

# Start VM in background
sub cmd_start ( $self, @args )
{
	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	return $vm->start;
}

# Stop VM
sub cmd_stop ( $self, @args )
{
	my $force  = 0;
	my $parser = Getopt::Long::Parser->new;
	$parser->configure('bundling');
	$parser->getoptionsfromarray( \@args, 'force|f' => \$force, )
	    or return EXIT_INVALID_ARGS;

	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	return $vm->stop($force);
}

# SSH into VM or run command
sub cmd_ssh ( $self, @args )
{
	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;

	# Uses SSH agent for authentication
	my $ssh = OpenHVF::SSH->new(
		host => 'localhost',
		port => $vm->ssh_port,
		user => 'root',
	);

	if (@args) {
		my $result = $ssh->run_command( join( ' ', @args ) );
		print $result->{stdout}        if $result->{stdout};
		print STDERR $result->{stderr} if $result->{stderr};
		return $result->{exit_code};
	}
	else {
		return $ssh->interactive;
	}
}

# Show console connection info
sub cmd_console ( $self, @args )
{
	my $vm           = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	my $console_port = $vm->console_port;
	my $ssh_port     = $vm->ssh_port;

	$self->{output}->info("Console access methods:");
	$self->{output}->info("  1. telnet localhost $console_port");
	$self->{output}->info("  2. ssh -p $ssh_port root\@localhost");

	return EXIT_SUCCESS;
}

# Run expect script
sub cmd_expect ( $self, @args )
{
	my $script = shift @args;
	if ( !defined $script ) {
		$self->{output}
		    ->error("Usage: openhvf expect <script> [args...]");
		return EXIT_INVALID_ARGS;
	}

	my $vm     = $self->_load_vm or return EXIT_VM_NOT_FOUND;
	my $expect = OpenHVF::Expect->new(
		host => 'localhost',
		port => $vm->console_port,
	);

	my $result = $expect->run_script( $script, @args );
	return $result ? EXIT_SUCCESS : EXIT_EXPECT_FAILED;
}

# Wait for SSH to become available
sub cmd_wait ( $self, @args )
{
	my $timeout = 120;
	my $parser  = Getopt::Long::Parser->new;
	$parser->configure('bundling');
	$parser->getoptionsfromarray( \@args, 'timeout=s' => \$timeout, )
	    or return EXIT_INVALID_ARGS;

	# Validate timeout is a positive integer
	if ( $timeout !~ /^\d+$/ ) {
		$self->{output}->error("Invalid timeout value: $timeout");
		return EXIT_INVALID_ARGS;
	}
	$timeout = int($timeout);
	if ( $timeout <= 0 ) {
		$self->{output}->error("Timeout must be a positive number");
		return EXIT_INVALID_ARGS;
	}

	my $vm = $self->_load_vm or return EXIT_VM_NOT_FOUND;

	if ( !$vm->wait_ssh($timeout) ) {
		$self->{output}->error("Timeout waiting for SSH");
		return EXIT_TIMEOUT;
	}

	$self->{output}->success("VM ready");
	return EXIT_SUCCESS;
}

# Image management
sub cmd_image ( $self, @args )
{
	my $action = shift @args;
	if ( !defined $action || $action !~ /^(download|list)$/ ) {
		$self->{output}->error("Usage: openhvf image <download|list>");
		return EXIT_INVALID_ARGS;
	}

	my $cache_dir = $self->{config}->cache_dir;
	my $image     = OpenHVF::Image->new($cache_dir);

	if ( $action eq 'list' ) {
		my $images = $image->list;
		$self->{output}->data( { images => $images } );
		return EXIT_SUCCESS;
	}

	my $version = shift @args // '7.8';

	$self->{output}->info("Downloading OpenBSD $version...");
	my $path = $image->download($version);
	if ( !defined $path ) {
		$self->{output}->error("Download failed");
		return EXIT_DOWNLOAD_FAILED;
	}
	$self->{output}->success("Downloaded: $path");
	return EXIT_SUCCESS;
}

# Initialize project
sub cmd_init ( $self, @args )
{
	my $dir         = shift @args // '.';
	my $openhvf_dir = "$dir/.openhvf";
	my $config_file = "$dir/.openhvfrc";

	if ( -f $config_file ) {
		$self->{output}->info("OpenHVF already initialized in $dir");
		return EXIT_SUCCESS;
	}

	# Check if directory is writable
	if ( !-d $dir ) {
		$self->{output}->error("Directory does not exist: $dir");
		return EXIT_ERROR;
	}
	if ( !-w $dir ) {
		$self->{output}->error("Cannot write to directory: $dir");
		return EXIT_ERROR;
	}

	require File::Path;
	eval {
		File::Path::make_path( "$openhvf_dir/vms",
			"$openhvf_dir/state" );
	};
	if ($@) {
		my $err = $@;
		$err =~ s/ at \S+ line \d+.*//s;
		$self->{output}->error("Cannot create directory: $err");
		return EXIT_ERROR;
	}

	# Create project config
	_write_file( $config_file, <<'EOF' );
# OpenHVF project configuration

cache_dir = ~/.cache/openhvf
state_dir = .openhvf/state
default_vm = default
EOF

	# Create default VM config
	_write_file( "$openhvf_dir/vms/default.conf", <<"EOF" );
# Default OpenBSD VM

name = openbsd-default
version = 7.8
memory = 2048
disk_size = 8G

ssh_port = 2222
console_port = 4444
EOF

	# Create .gitignore
	_write_file( "$openhvf_dir/.gitignore", <<'EOF' );
state/
*.log
EOF

	$self->{output}->success("Initialized OpenHVF in $dir");
	return EXIT_SUCCESS;
}

sub cmd_help ( $, @ )
{
	print <<'EOF';
Usage: openhvf [--vm <name>] <command> [options]

Commands:
  up                  Ensure VM is running (download, create, start)
  down                Stop VM gracefully
  destroy             Stop VM and delete disk image
  status              Show VM status
  start               Start VM in background
  stop [--force]      Stop VM
  ssh [command]       Open SSH session or run command
  console             Show console connection info
  expect <script>     Run expect script against console
  wait [--timeout=N]  Wait for VM to be ready (SSH available)
  image <cmd>         Manage images (download, list)
  init [dir]          Initialize .openhvf/ directory
  help                Show this help

Global Options:
  --vm <name>     VM to operate on (default: "default")
  --project <dir> Project root (default: auto-discover)
  --quiet, -q     Suppress informational output
  --help, -h      Show help

Examples:
  openhvf init
  openhvf up
  openhvf ssh "uname -a"
  openhvf wait --timeout=300
  openhvf --vm minimal up
EOF
	return EXIT_SUCCESS;
}

sub _write_file ( $path, $content )
{
	open my $fh, '>', $path or die "Cannot write $path: $!";
	print $fh $content;
	close $fh;
}

1;

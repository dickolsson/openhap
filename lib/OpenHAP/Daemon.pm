# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2025 Dick Olsson <hi@dickolsson.com>
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

package OpenHAP::Daemon;

use POSIX        qw(setsid);
use OpenHAP::Log qw(:all);

# $class->daemonize($logfile):
#	Fork into background, detach from terminal, and redirect
#	standard file descriptors. Returns in child process only.
#	Parent process exits successfully.
sub daemonize( $class, $logfile = '/var/log/openhapd.log' )
{
	my $pid = fork;
	unless ( defined $pid ) {
		log_err( 'Cannot fork: %s', $! );
		die "Cannot fork: $!";
	}
	exit 0 if $pid;    # Parent exits, child continues

	$DB::inhibit_exit = 0;
	setsid() or do {
		log_err( 'Cannot start new session: %s', $! );
		die "Cannot start new session: $!";
	};

	# Redirect standard file descriptors
	open STDIN, '<', '/dev/null' or do {
		log_err( 'Cannot read /dev/null: %s', $! );
		die "Cannot read /dev/null: $!";
	};
	open STDOUT, '>>', $logfile or do {
		log_err( 'Cannot write to %s: %s', $logfile, $! );
		die "Cannot write to $logfile: $!";
	};
	open STDERR, '>&', \*STDOUT or do {
		log_err( 'Cannot dup STDOUT: %s', $! );
		die "Cannot dup STDOUT: $!";
	};

	log_debug( 'Daemonized successfully, PID: %d', $$ );
	return;
}

# $class->write_pidfile($path):
#	Write current PID to file. Returns true on success.
sub write_pidfile( $class, $path )
{
	open my $fh, '>', $path or do {
		log_err( 'Cannot write PID file %s: %s', $path, $! );
		return;
	};

	print $fh "$$\n";
	close $fh;

	log_debug( 'Wrote PID %d to %s', $$, $path );
	return 1;
}

# $class->read_pidfile($path):
#	Read PID from file. Returns PID or undef if file doesn't exist
#	or cannot be read.
sub read_pidfile( $class, $path )
{
	return unless -f $path;

	open my $fh, '<', $path or do {
		log_warning( 'Cannot read PID file %s: %s', $path, $! );
		return;
	};

	my $pid = <$fh>;
	close $fh;

	return unless defined $pid;
	chomp $pid;
	return unless $pid =~ /^\d+$/;

	return $pid;
}

# $class->check_running($pidfile):
#	Check if daemon is running based on PID file.
#	Returns PID if running, undef otherwise.
sub check_running( $class, $pidfile )
{
	my $pid = $class->read_pidfile($pidfile);
	return unless defined $pid;

	# Check if process exists
	return unless kill 0, $pid;

	return $pid;
}

1;

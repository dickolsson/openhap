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

package OpenHAP::Log;

use Sys::Syslog qw(:standard :macros);
use Exporter 'import';

our @EXPORT_OK = qw(
    log_debug
    log_info
    log_notice
    log_warning
    log_err
    log_crit
    log_alert
    log_emerg
);

our %EXPORT_TAGS = ( all => \@EXPORT_OK );

# Log levels following syslog(3) conventions
use constant {
	LEVEL_DEBUG   => 0,
	LEVEL_INFO    => 1,
	LEVEL_NOTICE  => 2,
	LEVEL_WARNING => 3,
	LEVEL_ERR     => 4,
	LEVEL_CRIT    => 5,
	LEVEL_ALERT   => 6,
	LEVEL_EMERG   => 7,
};

# Map level names to numeric values
my %level_map = (
	debug   => LEVEL_DEBUG,
	info    => LEVEL_INFO,
	notice  => LEVEL_NOTICE,
	warning => LEVEL_WARNING,
	warn    => LEVEL_WARNING,
	err     => LEVEL_ERR,
	error   => LEVEL_ERR,
	crit    => LEVEL_CRIT,
	alert   => LEVEL_ALERT,
	emerg   => LEVEL_EMERG,
);

# Map level names to syslog priorities
my %syslog_priority = (
	debug   => LOG_DEBUG,
	info    => LOG_INFO,
	notice  => LOG_NOTICE,
	warning => LOG_WARNING,
	err     => LOG_ERR,
	crit    => LOG_CRIT,
	alert   => LOG_ALERT,
	emerg   => LOG_EMERG,
);

# Global state (module-level singleton)
my $state = {
	initialized => 0,
	foreground  => 0,
	level       => LEVEL_INFO,
	facility    => LOG_DAEMON,
	ident       => 'openhapd',
	verbose     => 0,
};

# $class->init(%args):
#	initialize the logging subsystem
#	%args:
#		ident      => program name for syslog (default: openhapd)
#		facility   => syslog facility (default: LOG_DAEMON)
#		foreground => log to stderr instead of syslog (default: 0)
#		level      => minimum log level (default: info)
#		verbose    => increase verbosity (default: 0)
sub init( $class, %args )
{
	$state->{ident}      = $args{ident}      // 'openhapd';
	$state->{foreground} = $args{foreground} // 0;
	$state->{verbose}    = $args{verbose}    // 0;

	# Parse log level
	if ( defined $args{level} ) {
		my $level = lc( $args{level} );
		if ( exists $level_map{$level} ) {
			$state->{level} = $level_map{$level};
		}
	}

	# Adjust level based on verbosity
	if ( $state->{verbose} > 0 ) {
		$state->{level} = LEVEL_DEBUG;
	}

	# Parse facility
	if ( defined $args{facility} ) {
		$state->{facility} = _parse_facility( $args{facility} );
	}

	# Open syslog if not in foreground mode
	if ( !$state->{foreground} ) {
		openlog( $state->{ident}, 'ndelay,pid', $state->{facility} );
	}

	$state->{initialized} = 1;
	return 1;
}

# $class->finalize():
#	close the logging subsystem
sub finalize($class)
{
	if ( $state->{initialized} && !$state->{foreground} ) {
		closelog();
	}
	$state->{initialized} = 0;
}

# $class->write_log($level, $message, @args):
#	log a message at the specified level
#	$level is a string: debug, info, notice, warning, err, crit, alert, emerg
#	$message is a format string (printf-style)
#	@args are format arguments
sub write_log( $class, $level, $message, @args )
{
	return unless $state->{initialized};

	$level = lc($level);
	my $numeric_level = $level_map{$level} // LEVEL_INFO;

	# Check if message should be logged
	return if $numeric_level < $state->{level};

	# Format message
	my $formatted = @args ? sprintf( $message, @args ) : $message;

	# Remove trailing newline (syslog adds its own)
	$formatted =~ s/\n+$//;

	if ( $state->{foreground} ) {
		_log_stderr( $level, $formatted );
	}
	else {
		_log_syslog( $level, $formatted );
	}
}

# Internal: log to stderr
sub _log_stderr( $level, $message )
{
	my $timestamp = _timestamp();
	my $prefix    = uc($level);

	# Color output for terminals (NO_COLOR honors user preference)
	my $colored = $message;
	if ( _is_interactive(*STDERR) && !$ENV{NO_COLOR} ) {
		$colored = _colorize( $level, $message );
		$prefix  = _colorize( $level, $prefix );
	}

	print STDERR "[$timestamp] $prefix: $colored\n";
}

# Internal: log to syslog
sub _log_syslog( $level, $message )
{
	my $priority = $syslog_priority{$level} // LOG_INFO;
	syslog( $priority, '%s', $message );
}

# Internal: generate timestamp for foreground mode
sub _timestamp()
{
	my @t = localtime;
	return sprintf '%04d-%02d-%02d %02d:%02d:%02d',
	    $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
}

# Internal: check if filehandle is connected to a terminal
sub _is_interactive($fh)
{
	# Check if the filehandle is connected to a terminal device
	# Uses -t operator which is the standard POSIX way
	return ( -t $fh ) ? 1 : 0;
}

# Internal: colorize message for terminal output
sub _colorize( $level, $message )
{
	my %colors = (
		debug   => "\e[36m",         # cyan
		info    => "\e[32m",         # green
		notice  => "\e[34m",         # blue
		warning => "\e[33m",         # yellow
		err     => "\e[31m",         # red
		crit    => "\e[1;31m",       # bold red
		alert   => "\e[1;35m",       # bold magenta
		emerg   => "\e[1;37;41m",    # bold white on red
	);

	my $reset = "\e[0m";
	my $color = $colors{$level} // '';

	return "$color$message$reset";
}

# Internal: parse facility name to constant
sub _parse_facility($facility)
{
	return $facility if $facility =~ /^\d+$/;

	my %facilities = (
		auth     => LOG_AUTH,
		authpriv => LOG_AUTHPRIV,
		cron     => LOG_CRON,
		daemon   => LOG_DAEMON,
		ftp      => LOG_FTP,
		kern     => LOG_KERN,
		local0   => LOG_LOCAL0,
		local1   => LOG_LOCAL1,
		local2   => LOG_LOCAL2,
		local3   => LOG_LOCAL3,
		local4   => LOG_LOCAL4,
		local5   => LOG_LOCAL5,
		local6   => LOG_LOCAL6,
		local7   => LOG_LOCAL7,
		lpr      => LOG_LPR,
		mail     => LOG_MAIL,
		news     => LOG_NEWS,
		syslog   => LOG_SYSLOG,
		user     => LOG_USER,
		uucp     => LOG_UUCP,
	);

	return $facilities{ lc($facility) } // LOG_DAEMON;
}

# Convenience functions for each log level
# These can be exported and called without the class

sub log_debug( $message, @args )
{
	__PACKAGE__->write_log( 'debug', $message, @args );
}

sub log_info( $message, @args )
{
	__PACKAGE__->write_log( 'info', $message, @args );
}

sub log_notice( $message, @args )
{
	__PACKAGE__->write_log( 'notice', $message, @args );
}

sub log_warning( $message, @args )
{
	__PACKAGE__->write_log( 'warning', $message, @args );
}

sub log_err( $message, @args )
{
	__PACKAGE__->write_log( 'err', $message, @args );
}

sub log_crit( $message, @args )
{
	__PACKAGE__->write_log( 'crit', $message, @args );
}

sub log_alert( $message, @args )
{
	__PACKAGE__->write_log( 'alert', $message, @args );
}

sub log_emerg( $message, @args )
{
	__PACKAGE__->write_log( 'emerg', $message, @args );
}

# Accessors for testing/inspection

sub is_initialized($class)
{
	return $state->{initialized};
}

sub get_level($class)
{
	return $state->{level};
}

sub is_foreground($class)
{
	return $state->{foreground};
}

1;

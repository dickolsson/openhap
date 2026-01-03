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

# OpenHAP::Log is now a thin wrapper around FuguLib::Log for backward compatibility
use FuguLib::Log;
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

# Singleton instance
my $logger;

# $class->init(%args):
#initialize the logging subsystem (wrapper around FuguLib::Log)
#%args:
#ident      => program name for syslog (default: openhapd)
#facility   => syslog facility (default: daemon)
#foreground => log to stderr instead of syslog (default: 0)
#level      => minimum log level (default: info)
#verbose    => increase verbosity (default: 0)
sub init( $class, %args )
{
	my $mode  = $args{foreground} ? 'stderr' : 'syslog';
	my $level = $args{level} // 'info';
	$level = 'debug' if $args{verbose};

	$logger = FuguLib::Log->new(
		mode     => $mode,
		ident    => $args{ident} // 'openhapd',
		level    => $level,
		facility => $args{facility} // 'daemon',
	);

	return 1;
}

# $class->finalize():
#close the logging subsystem
sub finalize($class)
{
	$logger = undef;
	return 1;
}

# $class->is_initialized():
#check if logging has been initialized
sub is_initialized($class)
{
	return defined $logger;
}

# $class->get_level():
#get current log level as integer (for backward compatibility)
sub get_level($class)
{
	return 0 unless defined $logger;
	return $logger->{level};    # Already numeric from FuguLib::Log
}

# $class->is_foreground():
#check if logging to stderr (not syslog)
sub is_foreground($class)
{
	return 0 unless defined $logger;
	return $logger->{mode} eq 'stderr';
}

# $class->write_log($level, $message, @args):
#low-level logging method (for backward compatibility)
sub write_log( $class, $level, $message, @args )
{
	$logger //= _default_logger();
	my %methods = (
		0 => 'debug',
		1 => 'info',
		2 => 'notice',
		3 => 'warning',
		4 => 'error',
		5 => 'crit',
	);
	my $method = $methods{$level} // 'info';
	$logger->$method( $message, @args );
}

# Exported logging functions - delegate to FuguLib::Log
sub log_debug( $message, @args )
{
	$logger //= _default_logger();
	$logger->debug( $message, @args );
}

sub log_info( $message, @args )
{
	$logger //= _default_logger();
	$logger->info( $message, @args );
}

sub log_notice( $message, @args )
{
	$logger //= _default_logger();
	$logger->notice( $message, @args );
}

sub log_warning( $message, @args )
{
	$logger //= _default_logger();
	$logger->warning( $message, @args );
}

sub log_err( $message, @args )
{
	$logger //= _default_logger();
	$logger->error( $message, @args );
}

sub log_crit( $message, @args )
{
	$logger //= _default_logger();
	$logger->crit( $message, @args );
}

sub log_alert( $message, @args )
{
	$logger //= _default_logger();
	$logger->crit( $message, @args )
	    ;    # FuguLib::Log doesn't have alert, use crit
}

sub log_emerg( $message, @args )
{
	$logger //= _default_logger();
	$logger->crit( $message, @args )
	    ;    # FuguLib::Log doesn't have emerg, use crit
}

sub _default_logger()
{
	# Create default logger if init wasn't called
	return FuguLib::Log->new(
		mode  => 'syslog',
		ident => 'openhapd',
		level => 'info',
	);
}

1;

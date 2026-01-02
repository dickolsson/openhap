# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2026 OpenHAP Contributors
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

package FuguLib::Signal;

# FuguLib::Signal - Robust signal handling for graceful shutdown
#
# Provides safe signal handler registration with cleanup and interrupt
# handling. Ensures processes can be interrupted cleanly without leaving
# orphaned resources.

# Global flag for interrupt detection
our $interrupted = 0;

# Stack of cleanup handlers
my @cleanup_handlers;

sub new($class)
{
	bless {
		handlers => {},
		original => {},
	}, $class;
}

# $self->setup_graceful_exit(@signals):
#	Setup handlers for graceful exit on specified signals
#	Calls all registered cleanup handlers and exits
sub setup_graceful_exit( $self, @signals )
{
	for my $sig (@signals) {
		$self->{original}{$sig} = $SIG{$sig} // 'DEFAULT';
		$SIG{$sig} = sub ($signal) {
			$interrupted = 1;
			$self->_run_cleanup_handlers($signal);
			exit 130;    # Standard exit code for SIGINT (128 + 2)
		};
		$self->{handlers}{$sig} = 1;
	}
	return $self;
}

# $self->setup_interrupt_flag(@signals):
#	Setup handlers that set interrupt flag without exiting
#	Allows long-running operations to check and exit cleanly
sub setup_interrupt_flag( $self, @signals )
{
	for my $sig (@signals) {
		$self->{original}{$sig} = $SIG{$sig} // 'DEFAULT';
		$SIG{$sig}              = sub ($) { $interrupted = 1; };
		$self->{handlers}{$sig} = 1;
	}
	return $self;
}

# $self->add_cleanup($handler):
#	Add cleanup handler to be called on signal
#	Handler receives signal name as argument
sub add_cleanup( $self, $handler )
{
	push @cleanup_handlers, $handler;
	return $self;
}

# $self->restore():
#	Restore original signal handlers
sub restore($self)
{
	for my $sig ( keys %{ $self->{handlers} } ) {
		$SIG{$sig} = $self->{original}{$sig};
	}
	$self->{handlers} = {};
	return $self;
}

# check_interrupted():
#	Check if process has been interrupted
#	Returns true if interrupt signal received
sub check_interrupted()
{
	return $interrupted;
}

# reset_interrupted():
#	Reset interrupt flag (for testing or manual control)
sub reset_interrupted()
{
	$interrupted = 0;
}

sub _run_cleanup_handlers( $self, $signal )
{
	for my $handler (@cleanup_handlers) {
		eval { $handler->($signal); };
	}
	@cleanup_handlers = ();
}

# DESTROY runs when object goes out of scope
sub DESTROY($self)
{
	$self->restore;
}

1;

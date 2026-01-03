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

package OpenHVF::Output;

# OpenHVF::Output now wraps FuguLib::Log for consistency
use FuguLib::Log;

sub new( $class, $quiet = 0 )
{
	my $mode   = $quiet ? 'quiet' : 'stderr';
	my $logger = FuguLib::Log->new(
		mode  => $mode,
		ident => 'openhvf',
		level => 'info',
	);
	bless { logger => $logger, quiet => $quiet }, $class;
}

sub info( $self, $message )
{
	return if $self->{quiet};
	$self->{logger}->info($message);
}

sub error( $self, $message )
{
	$self->{logger}->error( 'error: %s', $message );
}

sub success( $self, $message )
{
	return if $self->{quiet};
	$self->{logger}->info($message);
}

sub data( $self, $hashref )
{
	$self->_format_data($hashref);
}

sub _format_data( $self, $data, $indent = 0 )
{
	my $prefix = '  ' x $indent;

	for my $key ( sort keys %$data ) {
		my $value = $data->{$key};

		if ( ref $value eq 'HASH' ) {
			say "$prefix$key:";
			$self->_format_data( $value, $indent + 1 );
		}
		elsif ( ref $value eq 'ARRAY' ) {
			say "$prefix$key:";
			for my $item (@$value) {
				if ( ref $item ) {
					$self->_format_data( $item,
						$indent + 1 );
				}
				else {
					say "$prefix  - $item";
				}
			}
		}
		else {
			$value //= '';
			say "$prefix$key: $value";
		}
	}
}

sub pid( $self, $name, $pid )
{
	say "Started $name (PID: $pid)";
}

1;

#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('OpenHVF::QMP');

# Test object creation
{
	my $qmp = OpenHVF::QMP->new('/tmp/test-qmp.sock');
	ok(defined $qmp, 'QMP object created');
	is($qmp->{socket_path}, '/tmp/test-qmp.sock', 'Socket path set correctly');
	is($qmp->{connected}, 0, 'Not connected initially');
}

# Test connection failure to non-existent socket
{
	my $qmp = OpenHVF::QMP->new('/tmp/nonexistent-qmp.sock');
	my $result = $qmp->open_connection;
	is($result, 0, 'Connection fails for non-existent socket');
}

# Test disconnect on unconnected socket
{
	my $qmp = OpenHVF::QMP->new('/tmp/test-qmp.sock');
	my $result = $qmp->disconnect;
	ok(defined $result, 'Disconnect returns object');
	is($qmp->{connected}, 0, 'Still not connected after disconnect');
}

# Test run_command on unconnected socket returns undef
{
	my $qmp = OpenHVF::QMP->new('/tmp/test-qmp.sock');
	my $result = $qmp->run_command('query-status');
	is($result, undef, 'run_command returns undef when not connected');
}

done_testing();

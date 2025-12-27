#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

# Skip if Net::SSH2 not available
BEGIN {
    eval { require Net::SSH2 };
    if ($@) {
	plan skip_all => 'Net::SSH2 not available';
    }
}

use_ok('OpenHVF::SSH');

# Test constants
is(OpenHVF::SSH::EXIT_SUCCESS(), 0, 'EXIT_SUCCESS is 0');
is(OpenHVF::SSH::EXIT_ERROR(), 1, 'EXIT_ERROR is 1');
is(OpenHVF::SSH::DEFAULT_TIMEOUT(), 10, 'DEFAULT_TIMEOUT is 10');
is(OpenHVF::SSH::BUFFER_SIZE(), 32768, 'BUFFER_SIZE is 32768');

# Test object creation
{
    my $ssh = OpenHVF::SSH->new(host => 'localhost', port => 22);
    ok(defined $ssh, 'SSH object created');
    is($ssh->{host}, 'localhost', 'host stored');
    is($ssh->{port}, 22, 'port stored');
}

# Test object creation with default port
{
    my $ssh = OpenHVF::SSH->new(host => 'example.com');
    is($ssh->{port}, 22, 'default port is 22');
}

# Test wait_available to non-existent host returns false
{
    my $ssh = OpenHVF::SSH->new(host => 'localhost', port => 59999);
    my $result = $ssh->wait_available(1);
    ok(!$result, 'wait_available to closed port returns false');
}

# Test is_available
{
    my $ssh = OpenHVF::SSH->new(host => 'localhost', port => 59999);
    ok(!$ssh->is_available, 'is_available false for closed port');
}

done_testing();

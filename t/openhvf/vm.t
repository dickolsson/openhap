#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('OpenHVF::VM');

# Memory and CPU constants
{
	ok(defined &OpenHVF::VM::MEMORY_DEFAULT, 'MEMORY_DEFAULT defined');
	is(OpenHVF::VM::MEMORY_DEFAULT(), '1G', 'Default memory is 1G');
	ok(defined &OpenHVF::VM::CPU_COUNT, 'CPU_COUNT defined');
	is(OpenHVF::VM::CPU_COUNT(), 2, 'Default CPU count is 2');
}

# Exit code constants
{
	is(OpenHVF::VM::EXIT_SUCCESS(), 0, 'EXIT_SUCCESS is 0');
	is(OpenHVF::VM::EXIT_ERROR(), 1, 'EXIT_ERROR is 1');
	is(OpenHVF::VM::EXIT_VM_RUNNING(), 5, 'EXIT_VM_RUNNING is 5');
	is(OpenHVF::VM::EXIT_VM_NOT_RUNNING(), 6, 'EXIT_VM_NOT_RUNNING is 6');
	is(OpenHVF::VM::EXIT_TIMEOUT(), 7, 'EXIT_TIMEOUT is 7');
}

done_testing();

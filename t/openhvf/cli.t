#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);
use Cwd qw(getcwd);

# CLI depends on SSH which requires Net::SSH2
BEGIN {
    eval { require Net::SSH2 };
    if ($@) {
	plan skip_all => 'Net::SSH2 not available';
    }
}

use_ok('OpenHVF::CLI');

# Test help command returns success

# Test help command returns success (exit code 0)
{
    my $result = OpenHVF::CLI->run('help');
    is($result, 0, 'help command returns success');
}

# Test unknown command returns error (exit code 2 = invalid args)
{
    # Suppress warning
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('unknown_command');
    is($result, 2, 'unknown command returns invalid args exit code');
}

# ============================================================
# Robustness tests (from ROBUSTNESS-REPORT.md)
# ============================================================

# Issue 2: Permission denied during init (readonly directory)
SKIP: {
    skip "Cannot test permission issues as root", 2 if $< == 0;
    
    my $tmpdir = tempdir(CLEANUP => 1);
    my $readonly = "$tmpdir/readonly";
    mkdir $readonly;
    chmod 0555, $readonly;
    
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('init', $readonly);
    
    chmod 0755, $readonly;  # cleanup
    
    is($result, 1, 'init on readonly dir returns EXIT_ERROR');
}

# Issue 2: Init on non-existent directory
{
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('init', '/nonexistent/path/should/fail');
    is($result, 1, 'init on non-existent dir returns EXIT_ERROR');
}

# Issue 5: Non-existent project path
{
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('--project=/nonexistent/path', 'status');
    is($result, 3, 'non-existent project path returns EXIT_CONFIG_ERROR');
}

# Issue 6: Non-numeric timeout value
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $orig_dir = getcwd();
    chdir $tmpdir;
    
    # Initialize project first
    OpenHVF::CLI->run('init');
    
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('wait', '--timeout=abc');
    
    chdir $orig_dir;
    
    is($result, 2, 'non-numeric timeout returns EXIT_INVALID_ARGS');
}

# Issue 6: Zero timeout value
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $orig_dir = getcwd();
    chdir $tmpdir;
    
    # Initialize project first
    OpenHVF::CLI->run('init');
    
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('wait', '--timeout=0');
    
    chdir $orig_dir;
    
    is($result, 2, 'zero timeout returns EXIT_INVALID_ARGS');
}

# Issue 6: Negative timeout value (as string)
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $orig_dir = getcwd();
    chdir $tmpdir;
    
    # Initialize project first
    OpenHVF::CLI->run('init');
    
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('wait', '--timeout=-10');
    
    chdir $orig_dir;
    
    is($result, 2, 'negative timeout returns EXIT_INVALID_ARGS');
}

# Issue 1: Long VM name via CLI
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $orig_dir = getcwd();
    chdir $tmpdir;
    
    # Initialize project first
    OpenHVF::CLI->run('init');
    
    my $long_name = 'x' x 10000;
    local $SIG{__WARN__} = sub {};
    my $result = OpenHVF::CLI->run('--vm', $long_name, 'status');
    
    chdir $orig_dir;
    
    is($result, 1, 'extremely long VM name returns EXIT_ERROR');
}

# Init command is idempotent
{
    my $tmpdir = tempdir(CLEANUP => 1);
    
    my $result1 = OpenHVF::CLI->run('init', $tmpdir);
    is($result1, 0, 'first init returns success');
    
    my $result2 = OpenHVF::CLI->run('init', $tmpdir);
    is($result2, 0, 'second init (idempotent) returns success');
}

done_testing();

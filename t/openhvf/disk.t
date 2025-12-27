#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);

use_ok('OpenHVF::Disk');

# Test object creation
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $disk = OpenHVF::Disk->new($tmpdir);
    ok(defined $disk, 'Disk object created');
}

# Test path generation
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $disk = OpenHVF::Disk->new($tmpdir);
    
    my $path = $disk->path('test');
    like($path, qr/test.*disk\.qcow2$/, 'path includes VM name and disk.qcow2');
}

# Test exists returns false for non-existent disk
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $disk = OpenHVF::Disk->new($tmpdir);
    
    ok(!$disk->disk_exists('test'), 'disk_exists returns false for missing disk');
}

# Test remove on non-existent disk
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $disk = OpenHVF::Disk->new($tmpdir);
    
    my $result = $disk->remove('test');
    ok($result, 'remove returns true for non-existent disk');
}

# Skip tests that require qemu-img
SKIP: {
    my $has_qemu = `which qemu-img 2>/dev/null`;
    skip 'qemu-img not installed', 2 unless $has_qemu;
    
    my $tmpdir = tempdir(CLEANUP => 1);
    my $disk = OpenHVF::Disk->new($tmpdir);
    
    # Test disk creation
    my $path = $disk->create('test', '1G');
    ok(defined $path, 'create returns path');
    ok(-f $path, 'disk file created');
}

done_testing();

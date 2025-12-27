#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);

use_ok('OpenHVF::Image');

# Test constants
is(OpenHVF::Image::BASE_URL(), 'https://cdn.openbsd.org/pub/OpenBSD',
    'BASE_URL is correct');
is(OpenHVF::Image::ARCH(), 'arm64',
    'ARCH is correct');

# Test object creation
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $image = OpenHVF::Image->new($tmpdir);
    ok(defined $image, 'Image object created');
    ok(-d $tmpdir, 'Cache directory exists');
}

# Test cache filename generation
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $image = OpenHVF::Image->new($tmpdir);
    
    my $filename = $image->_cache_filename('7.8');
    is($filename, 'miniroot78.img', 'Cache filename generated correctly');
}

# Test image filename generation (as used on OpenBSD CDN)
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $image = OpenHVF::Image->new($tmpdir);
    
    my $filename = $image->_image_filename('7.8');
    is($filename, 'miniroot78.img', 'Image filename generated correctly');
}

# Test path returns undef for missing image
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $image = OpenHVF::Image->new($tmpdir);
    
    my $path = $image->path('7.8');
    is($path, undef, 'path returns undef for missing image');
}

# Test list returns empty for empty cache
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $image = OpenHVF::Image->new($tmpdir);
    
    my $list = $image->list;
    is(ref $list, 'ARRAY', 'list returns array ref');
    is(scalar @$list, 0, 'list is empty for empty cache');
}

# Test remove on non-existent image
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $image = OpenHVF::Image->new($tmpdir);
    
    my $result = $image->remove('7.8');
    ok($result, 'remove returns true for non-existent image');
}

done_testing();

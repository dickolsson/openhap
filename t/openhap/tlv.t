#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

# Test TLV encoding/decoding
use_ok('OpenHAP::TLV');

# Test basic encoding
my $encoded = OpenHAP::TLV::encode(
    0x06 => pack('C', 1),  # State = 1
    0x00 => pack('C', 0),  # Method = 0
);

ok(defined $encoded, 'TLV encoding returns data');
is(length($encoded), 6, 'TLV encoding has correct length');

# Test decoding
my %decoded = OpenHAP::TLV::decode($encoded);
is_deeply(\%decoded, {
    0x06 => pack('C', 1),
    0x00 => pack('C', 0),
}, 'TLV decoding matches original');

# Test with longer values
my $long_value = 'x' x 300;
my $encoded_long = OpenHAP::TLV::encode(
    0x01 => $long_value,
);

ok(length($encoded_long) > 300, 'Long value is encoded with chunks');

my %decoded_long = OpenHAP::TLV::decode($encoded_long);
is($decoded_long{0x01}, $long_value, 'Long value decoded correctly');

done_testing();

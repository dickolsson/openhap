#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('OpenHAP::HTTP');

# Test request parsing
my $request_data = "GET /accessories HTTP/1.1\r\n" .
                   "Host: localhost\r\n" .
                   "Content-Type: application/hap+json\r\n" .
                   "\r\n";

my $request = OpenHAP::HTTP::parse($request_data);

is($request->{method}, 'GET', 'Method parsed correctly');
is($request->{path}, '/accessories', 'Path parsed correctly');
is($request->{version}, '1.1', 'Version parsed correctly');
is($request->{headers}{'host'}, 'localhost', 'Headers parsed correctly');

# Test POST with body
my $post_data = "POST /characteristics HTTP/1.1\r\n" .
                "Content-Length: 13\r\n" .
                "\r\n" .
                '{"test":true}';

my $post = OpenHAP::HTTP::parse($post_data);
is($post->{method}, 'POST', 'POST method parsed');
is($post->{body}, '{"test":true}', 'Body parsed correctly');

# Test response building
my $response = OpenHAP::HTTP::build_response(
    status => 200,
    headers => { 'Content-Type' => 'application/hap+json' },
    body => '{"status":"ok"}',
);

like($response, qr/HTTP\/1\.1 200 OK/, 'Response has status line');
like($response, qr/Content-Type: application\/hap\+json/, 'Response has headers');
like($response, qr/Content-Length: 15/, 'Response has content-length');
like($response, qr/\{"status":"ok"\}$/, 'Response has body');

done_testing();

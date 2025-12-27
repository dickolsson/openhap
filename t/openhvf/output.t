#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('OpenHVF::Output');

# Test normal mode
{
    my $output = OpenHVF::Output->new(0);
    ok(defined $output, 'Output object created');
}

# Test quiet mode
{
    my $output = OpenHVF::Output->new(1);
    ok(defined $output, 'Output object created in quiet mode');
}

# Test quiet mode suppresses info
{
    my $output = OpenHVF::Output->new(1);
    # Just verify it doesn't crash in quiet mode
    $output->info('test message');
    pass('info works in quiet mode');
}

# Test data formatting
{
    my $output = OpenHVF::Output->new(1);
    my $data = {key => 'value'};
    
    # Capture output
    my $captured = '';
    {
        local *STDOUT;
        open STDOUT, '>', \$captured;
        $output->data($data);
    }
    
    like($captured, qr/key:\s*value/, 'data output contains key/value');
}

done_testing();

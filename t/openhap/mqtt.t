#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('OpenHAP::MQTT');

# Test MQTT client creation
{
    my $mqtt = OpenHAP::MQTT->new(
        host => '192.168.1.100',
        port => 1883,
    );
    
    ok(defined $mqtt, 'MQTT client created');
    isa_ok($mqtt, 'OpenHAP::MQTT');
    is($mqtt->{host}, '192.168.1.100', 'Host set correctly');
    is($mqtt->{port}, 1883, 'Port set correctly');
}

# Test default values
{
    my $mqtt = OpenHAP::MQTT->new();
    
    is($mqtt->{host}, '127.0.0.1', 'Default host is localhost');
    is($mqtt->{port}, 1883, 'Default port is 1883');
    ok(!$mqtt->{connected}, 'Not connected by default');
}

# Test with credentials
{
    my $mqtt = OpenHAP::MQTT->new(
        host => 'broker.example.com',
        port => 8883,
        username => 'testuser',
        password => 'testpass',
    );
    
    is($mqtt->{username}, 'testuser', 'Username stored');
    is($mqtt->{password}, 'testpass', 'Password stored');
}

# Test subscription storage
{
    my $mqtt = OpenHAP::MQTT->new();
    
    my $callback_called = 0;
    my $callback = sub { $callback_called = 1 };
    
    $mqtt->subscribe('test/topic', $callback);
    
    ok(exists $mqtt->{subscriptions}{'test/topic'}, 'Subscription stored');
    is(ref $mqtt->{subscriptions}{'test/topic'}, 'CODE', 'Callback is code ref');
}

# Test multiple subscriptions
{
    my $mqtt = OpenHAP::MQTT->new();
    
    $mqtt->subscribe('topic1', sub { });
    $mqtt->subscribe('topic2', sub { });
    $mqtt->subscribe('topic3', sub { });
    
    is(scalar keys %{$mqtt->{subscriptions}}, 3, 'Three subscriptions stored');
}

# Test is_connected
{
    my $mqtt = OpenHAP::MQTT->new();
    
    ok(!$mqtt->is_connected(), 'Not connected initially');
    
    $mqtt->{connected} = 1;
    ok($mqtt->is_connected(), 'Connected after flag set');
}

# Test disconnect
{
    my $mqtt = OpenHAP::MQTT->new();
    
    $mqtt->{connected} = 1;
    $mqtt->{client} = 'dummy';
    
    $mqtt->disconnect();
    
    ok(!$mqtt->is_connected(), 'Not connected after disconnect');
    ok(!defined $mqtt->{client}, 'Client cleared');
}

# Test connect without Net::MQTT::Simple
SKIP: {
    skip 'Net::MQTT::Simple may be installed', 1 if eval { require Net::MQTT::Simple; 1 };
    
    my $mqtt = OpenHAP::MQTT->new();
    my $result = $mqtt->mqtt_connect();
    
    ok(!$result, 'Connect fails without Net::MQTT::Simple');
}

# Test publish when not connected
{
    my $mqtt = OpenHAP::MQTT->new();
    
    # Should not die, just return early
    eval {
        $mqtt->publish('test/topic', 'test payload');
    };
    ok(!$@, 'Publish when not connected does not die');
}

# Test topic matching - exact match
{
    my $mqtt = OpenHAP::MQTT->new();
    
    ok($mqtt->_topic_matches('stat/device/POWER', 'stat/device/POWER'),
        'Exact topic match');
    ok(!$mqtt->_topic_matches('stat/device/POWER', 'stat/device/RESULT'),
        'Different topic no match');
}

# Test topic matching - single level wildcard (+)
{
    my $mqtt = OpenHAP::MQTT->new();
    
    ok($mqtt->_topic_matches('stat/+/POWER', 'stat/device1/POWER'),
        'Single wildcard matches');
    ok($mqtt->_topic_matches('stat/+/POWER', 'stat/device2/POWER'),
        'Single wildcard matches different device');
    ok(!$mqtt->_topic_matches('stat/+/POWER', 'stat/device1/RESULT'),
        'Single wildcard requires rest to match');
    ok(!$mqtt->_topic_matches('stat/+/POWER', 'stat/a/b/POWER'),
        'Single wildcard only matches one level');
}

# Test topic matching - multi level wildcard (#)
{
    my $mqtt = OpenHAP::MQTT->new();
    
    ok($mqtt->_topic_matches('tele/#', 'tele/device/SENSOR'),
        'Multi wildcard matches');
    ok($mqtt->_topic_matches('tele/#', 'tele/device/sub/SENSOR'),
        'Multi wildcard matches multiple levels');
    ok($mqtt->_topic_matches('tele/device/#', 'tele/device/SENSOR'),
        'Multi wildcard at end');
    ok(!$mqtt->_topic_matches('stat/#', 'tele/device/SENSOR'),
        'Multi wildcard prefix must match');
}

# Test topic matching - combined wildcards
{
    my $mqtt = OpenHAP::MQTT->new();
    
    ok($mqtt->_topic_matches('+/+/SENSOR', 'tele/device/SENSOR'),
        'Multiple single wildcards');
    ok($mqtt->_topic_matches('stat/+/#', 'stat/device/POWER'),
        'Single then multi wildcard');
    ok($mqtt->_topic_matches('stat/+/#', 'stat/device/sub/level/POWER'),
        'Single then multi wildcard multiple levels');
}

# Test unsubscribe
{
    my $mqtt = OpenHAP::MQTT->new();
    
    $mqtt->subscribe('topic1', sub { });
    $mqtt->subscribe('topic2', sub { });
    
    is(scalar keys %{$mqtt->{subscriptions}}, 2, 'Two subscriptions');
    
    $mqtt->unsubscribe('topic1');
    
    is(scalar keys %{$mqtt->{subscriptions}}, 1, 'One subscription after unsubscribe');
    ok(!exists $mqtt->{subscriptions}{'topic1'}, 'topic1 removed');
    ok(exists $mqtt->{subscriptions}{'topic2'}, 'topic2 still exists');
}

# Test subscriptions accessor
{
    my $mqtt = OpenHAP::MQTT->new();
    
    $mqtt->subscribe('topic1', sub { });
    $mqtt->subscribe('topic2', sub { });
    
    my @topics = sort $mqtt->subscriptions();
    is_deeply(\@topics, ['topic1', 'topic2'], 'subscriptions() returns topics');
}

# Test message dispatch
{
    my $mqtt = OpenHAP::MQTT->new();
    
    my $received_payload;
    $mqtt->subscribe('stat/device/POWER', sub($payload) {
        $received_payload = $payload;
    });
    
    my $count = $mqtt->_dispatch_message('stat/device/POWER', 'ON');
    
    is($count, 1, 'One callback dispatched');
    is($received_payload, 'ON', 'Payload passed to callback');
}

# Test message dispatch with wildcard
{
    my $mqtt = OpenHAP::MQTT->new();
    
    my @received;
    $mqtt->subscribe('stat/+/POWER', sub($payload) {
        push @received, $payload;
    });
    
    $mqtt->_dispatch_message('stat/device1/POWER', 'ON');
    $mqtt->_dispatch_message('stat/device2/POWER', 'OFF');
    
    is(scalar @received, 2, 'Two messages dispatched');
    is($received[0], 'ON', 'First payload correct');
    is($received[1], 'OFF', 'Second payload correct');
}

# Test tick when not connected
{
    my $mqtt = OpenHAP::MQTT->new();
    
    my $result = $mqtt->tick();
    is($result, 0, 'tick returns 0 when not connected');
}

# Test disconnect clears pending messages
{
    my $mqtt = OpenHAP::MQTT->new();
    
    push @{$mqtt->{pending_messages}}, ['topic', 'payload'];
    $mqtt->disconnect();
    
    is(scalar @{$mqtt->{pending_messages}}, 0, 'Pending messages cleared on disconnect');
}

done_testing();

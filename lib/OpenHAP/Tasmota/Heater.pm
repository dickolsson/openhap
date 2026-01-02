use v5.36;

package OpenHAP::Tasmota::Heater;
require OpenHAP::Accessory;
our @ISA = qw(OpenHAP::Accessory);
use OpenHAP::Service;
use OpenHAP::Characteristic;
use OpenHAP::Log qw(:all);

sub new ( $class, %args )
{
	my $self = $class->SUPER::new(
		aid          => $args{aid},
		name         => $args{name},
		model        => 'Tasmota Switch',
		manufacturer => 'OpenHAP',
		serial       => $args{serial} // 'HEAT-001',
	);

	$self->{mqtt_topic}  = $args{mqtt_topic};
	$self->{mqtt_client} = $args{mqtt_client};
	$self->{power_state} = 0;

	# Add Switch/Outlet service
	my $switch = OpenHAP::Service->new(
		type    => 'Switch',
		iid     => 10,
		primary => 1,
	);

	$switch->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'On',
			iid    => 11,
			format => 'bool',
			perms  => [ 'pr', 'pw', 'ev' ],
			value  => \$self->{power_state},
			on_set => sub { $self->_set_power(@_) },
		) );

	$self->add_service($switch);

	return $self;
}

sub subscribe_mqtt ($self)
{
	my $topic = $self->{mqtt_topic};

	return unless $self->{mqtt_client}->is_connected();

	log_debug( 'Heater %s subscribing to MQTT topics', $self->{name} );

	# Subscribe to power state updates
	$self->{mqtt_client}->subscribe(
		"stat/$topic/POWER",
		sub {
			my ($payload) = @_;
			$self->{power_state} = ( $payload eq 'ON' ) ? 1 : 0;
			$self->notify_change(11);
		} );
}

sub _set_power ( $self, $state )
{
	my $topic   = $self->{mqtt_topic};
	my $command = $state ? 'ON' : 'OFF';

	log_debug( 'Heater %s power set to %s', $self->{name}, $command );
	$self->{mqtt_client}->publish( "cmnd/$topic/POWER", $command );
}

1;

use v5.36;

package OpenHAP::Tasmota::Sensor;
require OpenHAP::Accessory;
our @ISA = qw(OpenHAP::Accessory);
use OpenHAP::Service;
use OpenHAP::Characteristic;
use OpenHAP::Log qw(:all);
use JSON::XS;

sub new( $class, %args )
{
	my $self = $class->SUPER::new(
		aid          => $args{aid},
		name         => $args{name},
		model        => 'Tasmota Sensor',
		manufacturer => 'OpenHAP',
		serial       => $args{serial} // 'SENS-001',
	);

	$self->{mqtt_topic}   = $args{mqtt_topic};
	$self->{mqtt_client}  = $args{mqtt_client};
	$self->{sensor_type}  = $args{sensor_type} // 'DS18B20';
	$self->{current_temp} = 20.0;

	# Add Temperature Sensor service
	my $sensor = OpenHAP::Service->new(
		type    => 'TemperatureSensor',
		iid     => 10,
		primary => 1,
	);

	$sensor->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'CurrentTemperature',
			iid    => 11,
			format => 'float',
			perms  => [ 'pr', 'ev' ],
			unit   => 'celsius',
			value  => \$self->{current_temp},
			min    => -40,
			max    => 100,
		) );

	$self->add_service($sensor);

	return $self;
}

sub subscribe_mqtt($self)
{
	my $topic = $self->{mqtt_topic};

	return unless $self->{mqtt_client}->is_connected();

	log_debug( 'Sensor %s subscribing to MQTT topics', $self->{name} );

	# Subscribe to sensor updates
	$self->{mqtt_client}->subscribe(
		"stat/$topic/STATUS8",
		sub($payload) {
			$self->_handle_sensor_data($payload);
		} );

	$self->{mqtt_client}->subscribe(
		"tele/$topic/SENSOR",
		sub($payload) {
			$self->_handle_sensor_data($payload);
		} );
}

sub _handle_sensor_data( $self, $payload )
{
	eval {
		my $data = decode_json($payload);

		# Try different sensor paths
		my $temp;
		if ( exists $data->{StatusSNS} ) {

			# STATUS8 response
			$temp = $data->{StatusSNS}{ $self->{sensor_type} }
			    {Temperature};
		}
		elsif ( exists $data->{ $self->{sensor_type} } ) {

			# Direct SENSOR response
			$temp = $data->{ $self->{sensor_type} }{Temperature};
		}

		if ( defined $temp ) {
			log_debug( 'Sensor %s temperature updated: %.1f°C',
				$self->{name}, $temp );
			$self->{current_temp} = $temp;
			$self->notify_change(11);
		}
	};

	if ($@) {
		warn "Error parsing sensor data: $@\n";
	}
}

1;

use v5.36;

package OpenHAP::Tasmota::Sensor;
require OpenHAP::Tasmota::Base;
our @ISA = qw(OpenHAP::Tasmota::Base);
use OpenHAP::Service;
use OpenHAP::Characteristic;

use JSON::XS;

# Supported sensor types (H5)
use constant SENSOR_TYPES =>
    qw(DS18B20 DHT11 DHT22 AM2301 BME280 BMP280 SHT3X SI7021);

sub new ( $class, %args )
{
	my $self = $class->SUPER::new(
		aid          => $args{aid},
		name         => $args{name},
		model        => 'Tasmota Sensor',
		manufacturer => 'OpenHAP',
		serial       => $args{serial} // 'SENS-001',
		mqtt_topic   => $args{mqtt_topic},
		mqtt_client  => $args{mqtt_client},
		fulltopic    => $args{fulltopic},              # H2
	);

	$self->{sensor_type}      = $args{sensor_type};    # undef = auto-detect
	$self->{sensor_index}     = $args{sensor_index};   # For indexed sensors
	$self->{current_temp}     = 20.0;
	$self->{current_humidity} = undef;
	$self->{has_humidity}     = $args{has_humidity} // 0;

	# Add Temperature Sensor service
	my $temp_sensor = OpenHAP::Service->new(
		type    => 'TemperatureSensor',
		iid     => 10,
		primary => 1,
	);

	$temp_sensor->add_characteristic(
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

	$self->add_service($temp_sensor);

	# Optionally add Humidity Sensor service (H5)
	if ( $self->{has_humidity} ) {
		$self->{current_humidity} = 50.0;

		my $humidity_sensor = OpenHAP::Service->new(
			type => 'HumiditySensor',
			iid  => 20,
		);

		$humidity_sensor->add_characteristic(
			OpenHAP::Characteristic->new(
				type   => 'CurrentRelativeHumidity',
				iid    => 21,
				format => 'float',
				perms  => [ 'pr', 'ev' ],
				unit   => 'percentage',
				value  => \$self->{current_humidity},
				min    => 0,
				max    => 100,
			) );

		$self->add_service($humidity_sensor);
	}

	return $self;
}

sub subscribe_mqtt ($self)
{
	# Call base class to set up standard subscriptions (C1, C2, C3)
	$self->SUPER::subscribe_mqtt();

	return unless $self->{mqtt_client}->is_connected();

	$OpenHAP::logger->debug(
		'Sensor %s subscribing to additional MQTT topics',
		$self->{name} );

	# Subscribe to STATUS8 for sensor data (when actively queried)
	$self->{mqtt_client}->subscribe(
		$self->_build_topic( 'stat', 'STATUS8' ),
		sub ( $recv_topic, $payload ) {
			$self->_handle_status8($payload);
		} );

	# Subscribe to STATUS10 for sensor data (recommended per spec)
	$self->{mqtt_client}->subscribe(
		$self->_build_topic( 'stat', 'STATUS10' ),
		sub ( $recv_topic, $payload ) {
			$self->_handle_status10($payload);
		} );
}

# Override to process sensor data from SENSOR messages
sub _process_sensor_data ( $self, $data )
{
	$self->_extract_sensor_values($data);
}

# Override to process sensor data from STATUS8 responses
sub _handle_status8 ( $self, $payload )
{
	eval {
		my $data = decode_json($payload);

		# STATUS8 wraps data in StatusSNS
		if ( exists $data->{StatusSNS} ) {

			# Extract temperature unit if present (H4)
			if ( exists $data->{StatusSNS}{TempUnit} ) {
				$self->{temp_unit} =
				    $data->{StatusSNS}{TempUnit};
			}

			$self->_extract_sensor_values( $data->{StatusSNS} );
		}
	};

	if ($@) {
		$OpenHAP::logger->error( 'Error parsing STATUS8 for %s: %s',
			$self->{name}, $@ );
	}
}

# Override to handle STATUS10 responses (recommended sensor query)
sub _handle_status10 ( $self, $payload )
{
	eval {
		my $data = decode_json($payload);

		# STATUS10 wraps data in StatusSNS (same as STATUS8)
		if ( exists $data->{StatusSNS} ) {
			if ( exists $data->{StatusSNS}{TempUnit} ) {
				$self->{temp_unit} =
				    $data->{StatusSNS}{TempUnit};
			}
			$self->_extract_sensor_values( $data->{StatusSNS} );
		}
	};

	if ($@) {
		$OpenHAP::logger->error( 'Error parsing STATUS10 for %s: %s',
			$self->{name}, $@ );
	}
}

# $self->_extract_sensor_values($data):
#	Extract temperature and humidity from sensor data (H5).
sub _extract_sensor_values ( $self, $data )
{
	my ( $temp, $humidity, $sensor_id ) = $self->_find_sensor_values($data);

	if ( defined $temp ) {

		# Convert to Celsius if needed (H4)
		$temp = $self->convert_temperature($temp);

		$OpenHAP::logger->debug(
			'Sensor %s temperature updated: %.1f°C',
			$self->{name}, $temp );
		$self->{current_temp} = $temp;
		$self->notify_change(11);
	}

	if ( defined $humidity && $self->{has_humidity} ) {
		$OpenHAP::logger->debug( 'Sensor %s humidity updated: %.1f%%',
			$self->{name}, $humidity );
		$self->{current_humidity} = $humidity;
		$self->notify_change(21);
	}

	# L3: Track sensor hardware ID
	if ( defined $sensor_id ) {
		$self->{sensor_id} = $sensor_id;
	}
}

# $self->_find_sensor_values($data):
#	Find temperature, humidity, and sensor ID in sensor data (H5, L3).
#	Handles multiple sensor types and indexed sensors.
sub _find_sensor_values ( $self, $data )
{
	my ( $temp, $humidity, $sensor_id );

	# If sensor type is specified, look for that specific sensor
	if ( defined $self->{sensor_type} ) {
		my $key = $self->{sensor_type};

		# Handle indexed sensors (e.g., DS18B20-1)
		if ( defined $self->{sensor_index} ) {
			$key .= '-' . $self->{sensor_index};
		}

		if ( exists $data->{$key} ) {
			$temp      = $data->{$key}{Temperature};
			$humidity  = $data->{$key}{Humidity};
			$sensor_id = $data->{$key}{Id};            # L3
		}
	}
	else {
		# Auto-detect: try each known sensor type (H5)
		for my $type (SENSOR_TYPES) {
			if ( exists $data->{$type} ) {
				$self->{sensor_type} = $type;
				$temp      = $data->{$type}{Temperature};
				$humidity  = $data->{$type}{Humidity};
				$sensor_id = $data->{$type}{Id};            # L3

				# Enable humidity if sensor supports it
				if ( defined $humidity
					&& !$self->{has_humidity} )
				{
					$OpenHAP::logger->debug(
'Sensor %s auto-detected humidity support',
						$self->{name} );
				}
				last;
			}

			# Check for indexed sensors (e.g., DS18B20-1)
			for my $i ( 1 .. 8 ) {
				my $indexed = "$type-$i";
				if ( exists $data->{$indexed} ) {
					$self->{sensor_type}  = $type;
					$self->{sensor_index} = $i;
					$temp = $data->{$indexed}{Temperature};
					$humidity = $data->{$indexed}{Humidity};
					$sensor_id = $data->{$indexed}{Id}; # L3
					last;
				}
			}
			last if defined $temp;
		}
	}

	return ( $temp, $humidity, $sensor_id );
}

1;


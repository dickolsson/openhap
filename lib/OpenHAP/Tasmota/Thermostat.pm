use v5.36;

package OpenHAP::Tasmota::Thermostat;
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
		model        => 'Tasmota Thermostat',
		manufacturer => 'OpenHAP',
		serial       => $args{serial} // 'TSTAT-001',
	);

	$self->{mqtt_topic}  = $args{mqtt_topic};
	$self->{mqtt_client} = $args{mqtt_client};

	# Current state
	$self->{current_temp}         = 20.0;
	$self->{target_temp}          = 20.0;
	$self->{heating_state}        = 0;      # 0=Off, 1=Heat, 2=Cool
	$self->{target_heating_state} = 0;

	# Add Thermostat service
	my $thermostat = OpenHAP::Service->new(
		type => 'Thermostat',
		iid  => 10,
	);

	$thermostat->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'CurrentHeatingCoolingState',
			iid    => 11,
			format => 'uint8',
			perms  => [ 'pr', 'ev' ],
			value  => \$self->{heating_state},
		) );

	$thermostat->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'TargetHeatingCoolingState',
			iid    => 12,
			format => 'uint8',
			perms  => [ 'pr', 'pw', 'ev' ],
			value  => \$self->{target_heating_state},
			on_set => sub { $self->_set_target_state(@_) },
		) );

	$thermostat->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'CurrentTemperature',
			iid    => 13,
			format => 'float',
			perms  => [ 'pr', 'ev' ],
			unit   => 'celsius',
			value  => \$self->{current_temp},
			min    => -40,
			max    => 100,
		) );

	$thermostat->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'TargetTemperature',
			iid    => 14,
			format => 'float',
			perms  => [ 'pr', 'pw', 'ev' ],
			unit   => 'celsius',
			value  => \$self->{target_temp},
			min    => 10,
			max    => 38,
			step   => 0.5,
			on_set => sub { $self->_set_target_temp(@_) },
		) );

	$thermostat->add_characteristic(
		OpenHAP::Characteristic->new(
			type   => 'TemperatureDisplayUnits',
			iid    => 15,
			format => 'uint8',
			perms  => [ 'pr', 'pw', 'ev' ],
			value  => 0,    # 0=Celsius, 1=Fahrenheit
		) );

	$self->add_service($thermostat);

	return $self;
}

sub subscribe_mqtt($self)
{
	my $topic = $self->{mqtt_topic};

	return unless $self->{mqtt_client}->is_connected();

	log_debug( 'Thermostat %s subscribing to MQTT topics', $self->{name} );

	# Subscribe to status updates
	$self->{mqtt_client}->subscribe(
		"stat/$topic/POWER",
		sub($payload) {
			$self->{heating_state} = ( $payload eq 'ON' ) ? 1 : 0;
			$self->notify_change(11);
		} );

	$self->{mqtt_client}->subscribe(
		"stat/$topic/STATUS8",
		sub($payload) {
			eval {
				my $data = decode_json($payload);
				if ( my $temp =
					$data->{StatusSNS}{DS18B20}{Temperature}
				    )
				{
					$self->{current_temp} = $temp;
					$self->notify_change(13);
					$self->_check_thermostat_logic();
				}
			};
		} );
}

sub _set_target_temp( $self, $temp )
{
	log_debug( 'Thermostat %s target temperature set to %.1f°C',
		$self->{name}, $temp );
	$self->{target_temp} = $temp;
	$self->_check_thermostat_logic();
}

sub _set_target_state( $self, $state )
{
	log_debug( 'Thermostat %s target heating state set to %d',
		$self->{name}, $state );
	$self->{target_heating_state} = $state;
	$self->_check_thermostat_logic();
}

sub _check_thermostat_logic($self)
{
	# Simple bang-bang controller with 0.5°C hysteresis
	my $hysteresis = 0.5;
	my $current    = $self->{current_temp};
	my $target     = $self->{target_temp};

	if ( $self->{target_heating_state} == 0 ) {

		# Target is OFF
		$self->_set_relay('OFF') if $self->{heating_state};
	}
	elsif ( $self->{target_heating_state} == 1 ) {

		# Target is HEAT
		if ( $current < $target - $hysteresis ) {
			$self->_set_relay('ON');
		}
		elsif ( $current > $target + $hysteresis ) {
			$self->_set_relay('OFF');
		}
	}
}

sub _set_relay( $self, $state )
{
	my $topic = $self->{mqtt_topic};
	log_debug( 'Thermostat %s relay set to %s', $self->{name}, $state );
	$self->{mqtt_client}->publish( "cmnd/$topic/POWER", $state );
}

1;

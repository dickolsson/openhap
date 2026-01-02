use v5.36;

package OpenHAP::HAP;
use IO::Socket::INET;
use IO::Select;
use JSON::XS;
use OpenHAP::HTTP;
use OpenHAP::Log qw(:all);
use OpenHAP::Session;
use OpenHAP::Pairing;
use OpenHAP::Storage;
use OpenHAP::Crypto;
use OpenHAP::Bridge;
use OpenHAP::PIN qw(normalize_pin);

sub new ( $class, %args )
{
	my $self = bless {
		port => $args{port}                               // 51827,
		pin => normalize_pin( $args{pin} // '1995-1018' ) // '19951018',
		name         => $args{name}         // 'OpenHAP Bridge',
		storage_path => $args{storage_path} // '/var/db/openhapd',

		bridge   => undef,
		storage  => undef,
		pairing  => undef,
		sessions => {},

		accessory_ltsk => undef,
		accessory_ltpk => undef,

		mqtt_client        => undef,
		mqtt_tick_interval => 0.1,     # MQTT poll interval in seconds
	}, $class;

	$self->_initialize();

	return $self;
}

sub _initialize ($self)
{
	# Initialize storage
	$self->{storage} =
	    OpenHAP::Storage->new( db_path => $self->{storage_path} );

	# Load or generate accessory keys
	my ( $ltsk, $ltpk ) = $self->{storage}->load_accessory_keys();
	unless ( $ltsk && $ltpk ) {
		( $ltsk, $ltpk ) = OpenHAP::Crypto::generate_keypair_ed25519();
		$self->{storage}->save_accessory_keys( $ltsk, $ltpk );
	}

	$self->{accessory_ltsk} = $ltsk;
	$self->{accessory_ltpk} = $ltpk;

	# Initialize pairing handler
	$self->{pairing} = OpenHAP::Pairing->new(
		pin            => $self->{pin},
		storage        => $self->{storage},
		accessory_ltsk => $self->{accessory_ltsk},
		accessory_ltpk => $self->{accessory_ltpk},
	);

	# Initialize bridge
	$self->{bridge} = OpenHAP::Bridge->new( name => $self->{name}, );
}

sub add_accessory ( $self, $accessory )
{
	$self->{bridge}->add_bridged_accessory($accessory);
}

# $self->_mqtt_resubscribe_accessories():
#	resubscribe all accessories to their MQTT topics
sub _mqtt_resubscribe_accessories ($self)
{
	my @accessories = $self->{bridge}->get_bridged_accessories();
	for my $acc (@accessories) {
		if ( $acc->can('subscribe_mqtt') ) {
			eval { $acc->subscribe_mqtt(); };
			log_err( 'Failed to resubscribe accessory: %s', $@ )
			    if $@;
		}
	}
}

# $self->set_mqtt_client($mqtt):
#	set the MQTT client for event loop integration
sub set_mqtt_client ( $self, $mqtt )
{
	$self->{mqtt_client} = $mqtt;
}

sub run ($self)
{
	my $server = IO::Socket::INET->new(
		LocalPort => $self->{port},
		Type      => SOCK_STREAM,
		Reuse     => 1,
		Listen    => 10,
	    )
	    or do {
		log_err( 'Cannot create server socket on port %d: %s',
			$self->{port}, $! );
		die "Cannot create server: $!";
	    };

	log_info( 'OpenHAP server listening on port %d', $self->{port} );
	log_debug( 'Pairing PIN: %s', $self->{pin} );

	my $select = IO::Select->new($server);

	# Use a short timeout to allow MQTT polling
	my $select_timeout          = $self->{mqtt_tick_interval};
	my $mqtt_reconnect_interval = 30;    # Try reconnect every 30 seconds
	my $last_mqtt_reconnect     = 0;

	while (1) {
		my @ready = $select->can_read($select_timeout);

		# Process MQTT messages if client is configured
		if ( $self->{mqtt_client} ) {
			if ( $self->{mqtt_client}->is_connected ) {
				$self->{mqtt_client}->tick(0);
			}
			else {
				# Try to reconnect periodically if disconnected
				my $now = time;
				if ( $now - $last_mqtt_reconnect >=
					$mqtt_reconnect_interval )
				{
					$last_mqtt_reconnect = $now;
					if ( $self->{mqtt_client}->reconnect() )
					{
						log_info(
'Reconnected to MQTT broker'
						);

						# Resubscribe devices
						$self
						    ->_mqtt_resubscribe_accessories
						    ();
					}
					else {
						log_debug(
'MQTT reconnection attempt failed, will retry'
						);
					}
				}
			}
		}

		for my $sock (@ready) {
			if ( $sock == $server ) {

				# New connection
				my $client = $server->accept();
				$select->add($client);
				$self->_init_session($client);
			}
			else {

				# Handle client data
				$self->_handle_client( $sock, $select );
			}
		}
	}
}

sub _init_session ( $self, $socket )
{
	log_debug( 'New client connection from %s', $socket->peerhost );
	$self->{sessions}{$socket} =
	    OpenHAP::Session->new( socket => $socket, );
}

sub _handle_client ( $self, $sock, $select )
{
	my $session = $self->{sessions}{$sock};
	my $data    = '';
	my $bytes   = $sock->sysread( $data, 65535 );

	if ( !$bytes ) {

		# Connection closed
		log_debug( 'Client disconnected: %s', $sock->peerhost );
		$select->remove($sock);
		delete $self->{sessions}{$sock};
		$sock->close();
		return;
	}

	# Decrypt if session is encrypted
	if ( $session->is_encrypted() ) {
		$data = $session->decrypt($data);
		unless ( defined $data ) {
			log_warning('Decryption failed for client session');
			$select->remove($sock);
			delete $self->{sessions}{$sock};
			$sock->close();
			return;
		}
	}

	# Parse HTTP request
	my $request = OpenHAP::HTTP::parse($data);

	# Dispatch request
	my $response = $self->_dispatch( $request, $session );

	# Encrypt if session is encrypted
	if ( $session->is_encrypted() ) {
		$response = $session->encrypt($response);
	}

	# Send response
	$sock->syswrite($response);
}

sub _dispatch ( $self, $request, $session )
{
	my $path   = $request->{path};
	my $method = $request->{method};
	log_debug( 'HTTP request: %s %s', $method, $path );

	# Pairing endpoints (no verification required)
	if ( $path eq '/pair-setup' && $method eq 'POST' ) {
		return $self->_handle_pair_setup( $request, $session );
	}

	if ( $path eq '/pair-verify' && $method eq 'POST' ) {
		return $self->_handle_pair_verify( $request, $session );
	}

	# All other endpoints require verification
	unless ( $session->is_verified() ) {
		return OpenHAP::HTTP::build_response(
			status  => 470,    # Connection Authorization Required
			headers => { 'Content-Type' => 'application/hap+json' },
		);
	}

	# Accessory endpoints
	if ( $path eq '/accessories' && $method eq 'GET' ) {
		return $self->_handle_accessories( $request, $session );
	}

	if ( $path eq '/characteristics' && $method eq 'GET' ) {
		return $self->_handle_characteristics_get( $request, $session );
	}

	if ( $path eq '/characteristics' && $method eq 'PUT' ) {
		return $self->_handle_characteristics_put( $request, $session );
	}

	# Not found
	return OpenHAP::HTTP::build_response(
		status  => 404,
		headers => { 'Content-Type' => 'text/plain' },
		body    => 'Not Found',
	);
}

sub _handle_pair_setup ( $self, $request, $session )
{
	log_debug('Handling pair-setup request');
	my $response_body =
	    $self->{pairing}->handle_pair_setup( $request->{body}, $session );

	return OpenHAP::HTTP::build_response(
		status  => 200,
		headers => { 'Content-Type' => 'application/pairing+tlv8' },
		body    => $response_body,
	);
}

sub _handle_pair_verify ( $self, $request, $session )
{
	log_debug('Handling pair-verify request');
	my $response_body =
	    $self->{pairing}->handle_pair_verify( $request->{body}, $session );

	return OpenHAP::HTTP::build_response(
		status  => 200,
		headers => { 'Content-Type' => 'application/pairing+tlv8' },
		body    => $response_body,
	);
}

sub _handle_accessories ( $self, $request, $session )
{
	my $json = encode_json( $self->{bridge}->to_json() );

	return OpenHAP::HTTP::build_response(
		status  => 200,
		headers => { 'Content-Type' => 'application/hap+json' },
		body    => $json,
	);
}

sub _handle_characteristics_get ( $self, $request, $session )
{
	# Parse query string: ?id=1.11,1.13,2.10
	my $query = $request->{path};
	$query =~ s/^.*\?//;
	log_debug( 'Reading characteristics: %s', $query );

	my %params;
	for my $pair ( split /&/, $query ) {
		my ( $key, $value ) = split /=/, $pair, 2;
		$params{$key} = $value;
	}

	my @ids = split /,/, ( $params{id} // '' );
	my @characteristics;

	for my $id (@ids) {
		my ( $aid, $iid ) = split /\./, $id;

		my $accessory = $self->{bridge}->get_accessory($aid);
		next unless $accessory;

		my $char = $accessory->get_characteristic($iid);
		next unless $char;

		push @characteristics,
		    {
			aid   => $aid + 0,
			iid   => $iid + 0,
			value => $char->get_value(),
		    };
	}

	my $json = encode_json( { characteristics => \@characteristics } );

	return OpenHAP::HTTP::build_response(
		status  => 200,
		headers => { 'Content-Type' => 'application/hap+json' },
		body    => $json,
	);
}

sub _handle_characteristics_put ( $self, $request, $session )
{
	log_debug('Writing characteristics');
	my $data = eval { decode_json( $request->{body} ) };
	return OpenHAP::HTTP::build_response( status => 400 ) unless $data;

	for my $item ( @{ $data->{characteristics} // [] } ) {
		my $aid   = $item->{aid};
		my $iid   = $item->{iid};
		my $value = $item->{value};

		my $accessory = $self->{bridge}->get_accessory($aid);
		next unless $accessory;

		my $char = $accessory->get_characteristic($iid);
		next unless $char;

		$char->set_value($value) if defined $value;

		# Enable/disable events
		if ( exists $item->{ev} ) {
			$char->enable_events( $item->{ev} );
		}
	}

	return OpenHAP::HTTP::build_response( status => 204, );
}

sub is_paired ($self)
{
	my $pairings = $self->{storage}->load_pairings();
	return scalar( keys %$pairings ) > 0;
}

sub get_config_number ($self)
{
	return $self->{storage}->get_config_number();
}

sub get_device_id ($self)
{
	# Generate a device ID from the public key
	my $id = unpack( 'H*', substr( $self->{accessory_ltpk}, 0, 6 ) );
	return join( ':', $id =~ /../g );
}

sub get_mdns_txt_records ($self)
{
	return {
		'c#' => $self->get_config_number(),
		'ff' => 0,
		'id' => $self->get_device_id(),
		'md' => $self->{name},
		'pv' => '1.1',
		's#' => 1,
		'sf' => $self->is_paired() ? 0 : 1,
		'ci' => 2,
	};
}

1;

use v5.36;

package OpenHAP::Service;

# HAP Service Type UUIDs
our %SERVICE_TYPES = (
	'AccessoryInformation' => '0000003E-0000-1000-8000-0026BB765291',
	'Thermostat'           => '0000004A-0000-1000-8000-0026BB765291',
	'Switch'               => '00000049-0000-1000-8000-0026BB765291',
	'TemperatureSensor'    => '0000008A-0000-1000-8000-0026BB765291',
	'Outlet'               => '00000047-0000-1000-8000-0026BB765291',
);

sub new ( $class, %args )
{

	my $type = $args{type}           // die "Service type required";
	my $uuid = $SERVICE_TYPES{$type} // $type;

	my $self = bless {
		type            => $uuid,
		iid             => $args{iid},
		characteristics => [],
		hidden          => $args{hidden}  // 0,
		primary         => $args{primary} // 0,
	}, $class;

	return $self;
}

sub add_characteristic ( $self, $characteristic )
{
	push @{ $self->{characteristics} }, $characteristic;
}

sub get_characteristic ( $self, $iid )
{

	for my $char ( @{ $self->{characteristics} } ) {
		return $char if $char->{iid} == $iid;
	}

	return;
}

sub get_characteristics ($self)
{
	return @{ $self->{characteristics} };
}

sub to_json ($self)
{

	my @chars;
	for my $char ( @{ $self->{characteristics} } ) {
		push @chars, $char->to_json();
	}

	my $json = {
		type            => $self->{type},
		iid             => $self->{iid},
		characteristics => \@chars,
	};

	$json->{hidden}  = \1 if $self->{hidden};
	$json->{primary} = \1 if $self->{primary};

	return $json;
}

1;

use v5.36;

package OpenHAP::TLV;

# TLV8 encoding/decoding for HomeKit Accessory Protocol
# Type-Length-Value with 8-bit type and length fields
# Values > 255 bytes are split into multiple chunks with same type

sub encode(%items)
{
	my $out = '';

	for my $type ( sort { $a <=> $b } keys %items ) {
		my $value = $items{$type};

		# Split values > 255 bytes into chunks
		while ( length($value) > 0 ) {
			my $chunk = substr( $value, 0, 255, '' );
			$out .= pack( 'CC', $type, length($chunk) ) . $chunk;
		}
	}

	return $out;
}

sub decode($data)
{
	my %items;
	my $pos = 0;

	while ( $pos < length($data) ) {
		my ( $type, $len ) = unpack( 'CC', substr( $data, $pos, 2 ) );
		$pos += 2;

		my $value = substr( $data, $pos, $len );
		$pos += $len;

		# Concatenate chunks with same type
		$items{$type} = ( $items{$type} // '' ) . $value;
	}

	return %items;
}

1;

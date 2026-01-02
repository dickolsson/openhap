use v5.36;

package OpenHAP::SRP;
use Math::BigInt lib => 'GMP';
use Digest::SHA qw(sha512);
use OpenHAP::Crypto;
use OpenHAP::PIN qw(normalize_pin);

# SRP-6a implementation for HAP
# Uses 3072-bit group from RFC 5054

sub new ( $class, %args )
{

	my $self = bless {
		username => $args{username}                  // 'Pair-Setup',
		password => normalize_pin( $args{password} ) // $args{password},

		# Group parameters (from OpenHAP::Crypto)
		N => Math::BigInt->from_hex(
			unpack( 'H*', $OpenHAP::Crypto::N_3072 )
		),
		g => Math::BigInt->new($OpenHAP::Crypto::g),

		# Session state
		salt => undef,
		v    => undef,
		b    => undef,
		B    => undef,
		A    => undef,
		S    => undef,
		K    => undef,
		M1   => undef,
		M2   => undef,
	}, $class;

	return $self;
}

sub generate_salt ($self)
{
	$self->{salt} = OpenHAP::Crypto::generate_random_bytes(16);
	return $self->{salt};
}

sub compute_verifier ( $self, $salt = undef, $password = undef )
{
	$salt     //= $self->{salt};
	$password //= $self->{password};

	# x = H(salt | H(username | ":" | password))
	my $inner   = sha512( $self->{username} . ':' . $password );
	my $x_bytes = sha512( $salt . $inner );
	my $x       = Math::BigInt->from_hex( unpack( 'H*', $x_bytes ) );

	# v = g^x mod N
	my $v = $self->{g}->bmodpow( $x, $self->{N} );

	$self->{v} = $v;
	return $v;
}

sub generate_server_public ($self)
{

	# Generate random b (256 bits)
	my $b_bytes = OpenHAP::Crypto::generate_random_bytes(32);
	$self->{b} = Math::BigInt->from_hex( unpack( 'H*', $b_bytes ) );

	# k = H(N | g)
	my $k_bytes = sha512(
		      pack( 'H*', $self->{N}->as_hex() )
		    . pack( 'H*', $self->{g}->as_hex() ) );
	my $k = Math::BigInt->from_hex( unpack( 'H*', $k_bytes ) );

	# B = (k*v + g^b) mod N
	my $B =
	    ( $k * $self->{v} + $self->{g}->bmodpow( $self->{b}, $self->{N} ) )
	    % $self->{N};

	$self->{B} = $B;
	return $B;
}

sub compute_session_key ( $self, $A )
{

	$self->{A} = Math::BigInt->from_hex( unpack( 'H*', $A ) );

	# u = H(A | B)
	my $A_bytes = pack( 'H*', $self->{A}->as_hex() );
	my $B_bytes = pack( 'H*', $self->{B}->as_hex() );
	my $u_bytes = sha512( $A_bytes . $B_bytes );
	my $u       = Math::BigInt->from_hex( unpack( 'H*', $u_bytes ) );

	# S = (A * v^u)^b mod N
	my $S =
	    ( $self->{A} * $self->{v}->bmodpow( $u, $self->{N} ) )
	    ->bmodpow( $self->{b}, $self->{N} );

	$self->{S} = $S;

	# K = H(S)
	my $S_bytes = pack( 'H*', $S->as_hex() );
	$self->{K} = sha512($S_bytes);

	return $self->{K};
}

sub verify_client_proof ( $self, $M1_client )
{

	# M1 = H(H(N) XOR H(g) | H(username) | salt | A | B | K)
	my $N_hash = sha512( pack( 'H*', $self->{N}->as_hex() ) );
	my $g_hash = sha512( pack( 'H*', $self->{g}->as_hex() ) );
	my $xor    = $N_hash ^ $g_hash;

	my $user_hash = sha512( $self->{username} );

	my $A_bytes = pack( 'H*', $self->{A}->as_hex() );
	my $B_bytes = pack( 'H*', $self->{B}->as_hex() );

	my $M1 =
	    sha512(   $xor
		    . $user_hash
		    . $self->{salt}
		    . $A_bytes
		    . $B_bytes
		    . $self->{K} );

	$self->{M1} = $M1;

	return $M1 eq $M1_client;
}

sub generate_server_proof ($self)
{
	die "SRP: M1 not set (verify_client_proof not called)"
	    if !defined $self->{M1};
	die "SRP: K not set (compute_session_key not called)"
	    if !defined $self->{K};

	# M2 = H(A | M1 | K)
	my $A_bytes = pack( 'H*', $self->{A}->as_hex() );
	my $M2      = sha512( $A_bytes . $self->{M1} . $self->{K} );

	$self->{M2} = $M2;

	return $M2;
}

sub get_session_key ($self)
{
	return $self->{K};
}

1;

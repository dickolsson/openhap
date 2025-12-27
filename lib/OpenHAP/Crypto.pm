use v5.36;

package OpenHAP::Crypto;
use OpenHAP::Log qw(:all);

use Crypt::Curve25519 ();
use Crypt::Ed25519    ();
use Crypt::AuthEnc::ChaCha20Poly1305
    qw(chacha20poly1305_encrypt_authenticate chacha20poly1305_decrypt_verify);
use Crypt::KeyDerivation qw(hkdf);
use Digest::SHA          qw(sha512);

# SRP-6a Parameters (3072-bit per HAP spec)
our $N_3072 = pack( 'H*',
	      'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'
	    . '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'
	    . 'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'
	    . 'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
	    . 'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D'
	    . 'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'
	    . '83655D23DCA3AD961C62F356208552BB9ED529077096966D'
	    . '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'
	    . 'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9'
	    . 'DE2BCBF6955817183995497CEA956AE515D2261898FA0510'
	    . '15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64'
	    . 'ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7'
	    . 'ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6B'
	    . 'F12FFA06D98A0864D87602733EC86A64521F2B18177B200C'
	    . 'BBE117577A615D6C770988C0BAD946E208E24FA074E5AB31'
	    . '43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF' );
our $g = 5;

sub generate_random_bytes($length)
{
	# Use /dev/urandom for random bytes
	open my $fh, '<', '/dev/urandom'
	    or die "Cannot open /dev/urandom: $!";
	my $n = read $fh, ( my $bytes ), $length;
	close $fh;
	die "Short read from /dev/urandom: got $n, expected $length"
	    if !defined $n || $n != $length;

	return $bytes;
}

sub generate_keypair_ed25519()
{
	log_debug('Generating new Ed25519 keypair');
	my ( $public_key, $secret_key ) = Crypt::Ed25519::generate_keypair();
	return ( $secret_key, $public_key );
}

sub sign_ed25519( $message, $secret_key, $public_key )
{
	return Crypt::Ed25519::sign( $message, $public_key, $secret_key );
}

sub verify_ed25519( $signature, $message, $public_key )
{
	return Crypt::Ed25519::verify( $message, $public_key, $signature );
}

sub generate_keypair_x25519()
{
	my $random = generate_random_bytes(32);
	my $secret = Crypt::Curve25519::curve25519_secret_key($random);
	my $public = Crypt::Curve25519::curve25519_public_key($secret);
	return ( $secret, $public );
}

sub derive_shared_secret( $our_secret, $their_public )
{
	return Crypt::Curve25519::curve25519_shared_secret( $our_secret,
		$their_public );
}

sub hkdf_sha512( $ikm, $salt, $info, $length )
{
	return hkdf( $ikm, $salt, 'SHA512', $length, $info );
}

sub chacha20_poly1305_encrypt( $key, $nonce, $plaintext, $aad = '' )
{
	my ( $ciphertext, $tag ) =
	    chacha20poly1305_encrypt_authenticate( $key, $nonce, $aad,
		$plaintext );

	return ( $ciphertext, $tag );
}

sub chacha20_poly1305_decrypt( $key, $nonce, $ciphertext, $tag, $aad = '' )
{
	my $plaintext =
	    chacha20poly1305_decrypt_verify( $key, $nonce, $aad, $ciphertext,
		$tag );

	return $plaintext;
}

1;

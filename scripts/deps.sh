#!/bin/sh
# Cross-platform dependency installer
# Handles both OS packages and CPAN modules from deps/*.txt
# Usage: deps.sh <environment> [type]
#   environment: runtime, test, or develop
#   type: pkg, cpan, or omit for both

set -e

ENV="$1"
TYPE_FILTER="${2:-all}"
[ -z "$ENV" ] && { echo "Usage: $0 <runtime|test|develop> [pkg|cpan]" >&2; exit 1; }

OS=$(uname)
DEPS_FILE="deps/${OS}.txt"

[ ! -f "$DEPS_FILE" ] && { echo "No dependencies for $OS" >&2; exit 0; }

# Separate packages by type
PKG_PACKAGES=""
CPAN_MODULES=""

while read -r env type name; do
	# Skip comments and empty lines
	case "$env" in
		''|\#*) continue ;;
	esac
	
	# Skip if not matching environment
	[ "$env" != "$ENV" ] && continue
	
	# Validate format
	if [ -z "$name" ] || [ -z "$type" ]; then
		echo "ERROR: Invalid format in $DEPS_FILE: $env $type $name" >&2
		echo "Expected: <environment> <pkg|cpan> <package-name>" >&2
		exit 1
	fi
	
	case "$type" in
		pkg)
			PKG_PACKAGES="$PKG_PACKAGES $name"
			;;
		cpan)
			CPAN_MODULES="$CPAN_MODULES $name"
			;;
		*)
			echo "ERROR: Unknown type '$type' (expected 'pkg' or 'cpan')" >&2
			exit 1
			;;
	esac
done < "$DEPS_FILE"

# Install OS packages
if [ -n "$PKG_PACKAGES" ] && [ "$TYPE_FILTER" = "all" -o "$TYPE_FILTER" = "pkg" ]; then
	echo "Installing OS packages:$PKG_PACKAGES"
	case "$OS" in
		OpenBSD)
			pkg_add $PKG_PACKAGES
			;;
		Linux)
			apt-get install -y $PKG_PACKAGES
			;;
		Darwin)
			brew install $PKG_PACKAGES
			;;
		*)
			echo "ERROR: Unknown OS: $OS" >&2
			exit 1
			;;
	esac
fi

# Install CPAN modules
if [ -n "$CPAN_MODULES" ] && [ "$TYPE_FILTER" = "all" -o "$TYPE_FILTER" = "cpan" ]; then
	echo "Installing CPAN modules:$CPAN_MODULES"
	
	# Install cpanm if not available
	if ! command -v cpanm >/dev/null 2>&1; then
		echo "Installing cpanminus..."
		curl -L https://cpanmin.us | perl - App::cpanminus
	fi
	
	# Determine installation target
	# If PERL5LIB is set and points to a local directory, install there
	# Otherwise, install system-wide (default behavior)
	CPANM_OPTS="--notest"
	if [ -n "$PERL5LIB" ]; then
		# Extract the first directory from PERL5LIB (may contain multiple paths)
		LOCAL_LIB=$(echo "$PERL5LIB" | cut -d: -f1)
		# Check if it's a local directory (contains 'local')
		case "$LOCAL_LIB" in
			*/local/*)
				# Extract the local directory root (e.g., /path/to/local)
				LOCAL_ROOT=$(echo "$LOCAL_LIB" | sed 's|\(.*\)/local/.*|\1/local|')
				echo "Installing to local directory: $LOCAL_ROOT"
				CPANM_OPTS="$CPANM_OPTS -l $LOCAL_ROOT"
				;;
		esac
	fi
	
	cpanm $CPANM_OPTS $CPAN_MODULES
fi

echo "Dependencies for $ENV installed successfully"

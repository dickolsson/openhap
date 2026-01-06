#!/bin/sh
# Cross-platform dependency installer
# Handles both OS packages and CPAN modules from deps/*.txt
# Usage: deps.sh <environment>
#   environment: runtime, test, or develop

set -e

ENV="$1"
[ -z "$ENV" ] && { echo "Usage: $0 <runtime|test|develop>" >&2; exit 1; }

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
if [ -n "$PKG_PACKAGES" ]; then
	echo "Installing OS packages:$PKG_PACKAGES"
	case "$OS" in
		OpenBSD)
			if command -v doas >/dev/null 2>&1; then
				doas pkg_add $PKG_PACKAGES
			else
				pkg_add $PKG_PACKAGES
			fi
			;;
		Linux)
			if command -v sudo >/dev/null 2>&1; then
				sudo apt-get install -y $PKG_PACKAGES
			else
				apt-get install -y $PKG_PACKAGES
			fi
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
if [ -n "$CPAN_MODULES" ]; then
	echo "Installing CPAN modules:$CPAN_MODULES"
	
	# Install cpanm if not available
	if ! command -v cpanm >/dev/null 2>&1; then
		echo "Installing cpanminus..."
		curl -L https://cpanmin.us | perl - App::cpanminus
	fi
	
	cpanm --notest $CPAN_MODULES
fi

echo "Dependencies for $ENV installed successfully"

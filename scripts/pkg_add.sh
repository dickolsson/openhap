#!/bin/sh
# Cross-platform package installer
# Usage: pkg_add.sh package [package ...]

OS=$(uname)

case "$OS" in
	OpenBSD)
		pkg_add "$@"
		;;
	Linux)
		apt-get install -y "$@"
		;;
	Darwin)
		brew install "$@"
		;;
	*)
		echo "ERROR: Unknown OS: $OS" >&2
		exit 1
		;;
esac

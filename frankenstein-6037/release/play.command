#!/bin/sh
# Frankenstein 6.037 launcher for macOS and Linux. Asks for the server, the
# account and the password, then starts the client. Double-click it in
# Finder (macOS) or run ./play.command from a terminal.
#
# Set these beforehand to skip the questions:
#   FRANK_SERVER=host:port FRANK_ACCOUNT=name FRANK_PASSWORD=... ./play.command
#   FRANK_ASSETS=/path/to/your/Graal/folder   (default: ./data beside this file)
#   FRANK_SERVER_NAME="3 Lab"                 (default: Login, the server's warp decides)
# Anything after the script name goes to the client as is, e.g.
#   ./play.command --renderer software
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$HERE"
BIN="$HERE/frankenstein-6037"
if [ ! -x "$BIN" ]; then
  chmod +x "$BIN" 2>/dev/null || true
fi
if [ "$(uname -s)" = Darwin ]; then
  # A zip downloaded with a browser is quarantined; an unsigned program in it
  # is then refused. This clears the mark on this folder only.
  xattr -dr com.apple.quarantine "$HERE" 2>/dev/null || true
fi

if [ -z "${FRANK_SERVER:-}" ]; then
  printf 'Server (host:port): '
  read -r FRANK_SERVER
fi
if [ -z "${FRANK_ACCOUNT:-}" ]; then
  printf 'Account: '
  read -r FRANK_ACCOUNT
fi
if [ -z "${FRANK_PASSWORD:-}" ]; then
  printf 'Password: '
  stty -echo 2>/dev/null || true
  read -r FRANK_PASSWORD
  stty echo 2>/dev/null || true
  echo
fi
ASSETS=${FRANK_ASSETS:-"$HERE/data"}
mkdir -p "$ASSETS"
export FRANK_PASSWORD

set -- --connect "$FRANK_SERVER" --account "$FRANK_ACCOUNT" --password-env FRANK_PASSWORD \
  --assets "$ASSETS" --download-files "$@"
if [ -n "${FRANK_SERVER_NAME:-}" ]; then
  set -- --server-name "$FRANK_SERVER_NAME" "$@"
fi
echo "Starting frankenstein-6037 (log below; close the window or press Ctrl-C to quit)"
exec "$BIN" "$@"

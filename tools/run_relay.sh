#!/bin/sh
# Standalone UDP relay for double-NAT hosts (Phase 16). Run this on any free
# VPS or always-on PC with a public UDP port, then point the lobby's
# "Use relay ip:port" at this machine's address. Runs until killed.
#   tools/run_relay.sh --port 24565
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
export HOME="$PROJECT_ROOT/.tmp-home"
exec "$GODOT_BIN" --headless --path . -- --relay "$@"

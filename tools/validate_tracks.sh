#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}

cd "$PROJECT_ROOT"
exec "$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/test_loop/test_loop.tscn

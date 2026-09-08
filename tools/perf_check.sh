#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
KART_COUNT=${1:-12}
DURATION_SECONDS=${2:-30}

cd "$PROJECT_ROOT"
exec "$GODOT_BIN" --path . res://scenes/test/perf_probe.tscn -- "$KART_COUNT" "$DURATION_SECONDS"

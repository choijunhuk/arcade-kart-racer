#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}

cd "$PROJECT_ROOT"
exec "$GODOT_BIN" --headless --path . --fixed-fps 480 tests/sim/run_ai_race.tscn -- "$@"

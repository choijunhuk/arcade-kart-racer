#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}

cd "$PROJECT_ROOT"

# Stream progress and the complete JSON summary; preserve Godot's exit status.
exec "$GODOT_BIN" --headless --path . --fixed-fps 60 tests/sim/run_ai_race.tscn -- "$@"

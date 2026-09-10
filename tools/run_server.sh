#!/bin/sh
# Standalone dedicated server launcher (Phase 16). Runs in the foreground
# until killed (Ctrl+C); pass extra flags through, e.g.:
#   tools/run_server.sh --port 24565 --track track_02 --laps 2 --ai 2 --max-players 8
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
export HOME="$PROJECT_ROOT/.tmp-home"
exec "$GODOT_BIN" --headless --path . -- --server "$@"

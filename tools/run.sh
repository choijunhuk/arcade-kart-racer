#!/bin/sh
# Run the game from source. Always refreshes the import/class-name cache first:
# after pulling new scripts, Godot's global class cache can be stale, which makes
# autoloads fail to compile and the race scene misbehave (instant FINISH, broken
# restart, wrong grid placement). Importing first is cheap and avoids that entirely.
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
cd "$PROJECT_ROOT"
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT_BIN" --path . "$@"

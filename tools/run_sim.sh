#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}

cd "$PROJECT_ROOT"

# Capture output (rather than exec) so the summary line can be pulled back
# out and echoed distinctly, without depending on jq/python being installed.
OUTPUT=$("$GODOT_BIN" --headless --path . --fixed-fps 480 tests/sim/run_ai_race.tscn -- "$@") || EXIT_CODE=$?
: "${EXIT_CODE:=0}"

printf '%s\n' "$OUTPUT"

SUMMARY=$(printf '%s\n' "$OUTPUT" | grep -o '"summary":{[^}]*}' || true)
if [ -n "$SUMMARY" ]; then
	printf 'summary: %s\n' "$SUMMARY"
fi

exit "$EXIT_CODE"

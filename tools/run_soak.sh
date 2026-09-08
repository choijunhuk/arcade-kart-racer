#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOAK_LOG=${SOAK_LOG:-$(mktemp "${TMPDIR:-/tmp}/kart-soak.XXXXXX")}
EXIT_CODE=0

"$PROJECT_ROOT/tools/run_sim.sh" --races 10 --difficulty normal --karts 8 --laps 3 --items on > "$SOAK_LOG" 2>&1 || EXIT_CODE=$?
cat "$SOAK_LOG"
printf '\nSOAK_LOG %s\n' "$SOAK_LOG"
# Godot can return 0 after push_error; stderr and stdout are both mandatory evidence.
if grep -Ei '(^|[^[:alnum:]_])(error|errors)([^[:alnum:]_]|$)' "$SOAK_LOG" > /dev/null; then
	printf 'SOAK FAIL: error line found (see raw log).\n' >&2
	exit 1
fi
if [ "$EXIT_CODE" -ne 0 ]; then
	exit "$EXIT_CODE"
fi
if ! grep -q '"success":true' "$SOAK_LOG"; then
	printf 'SOAK FAIL: simulator did not produce a successful result.\n' >&2
	exit 1
fi
printf 'SOAK PASS: 10 races, 8 karts, 3 laps, items on; no error lines.\n'

#!/bin/sh
# Real host/client processes; capture logs, bound runtime, and reap both on every exit.
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
export HOME="$PROJECT_ROOT/.tmp-home"
LOG_DIR="$PROJECT_ROOT/.omc/phase15-logs"
mkdir -p "$LOG_DIR"
label=${NET_TEST_LABEL:-loopback}
host_log="$LOG_DIR/$label-host.log"
client_log="$LOG_DIR/$label-client.log"
host_pid=
client_pid=
cleanup() {
  if [ -n "$host_pid" ]; then kill "$host_pid" 2>/dev/null || true; wait "$host_pid" 2>/dev/null || true; fi
  if [ -n "$client_pid" ]; then kill "$client_pid" 2>/dev/null || true; wait "$client_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
"$GODOT_BIN" --headless --path . -- --net-host --ai 6 --laps 1 "$@" >"$host_log" 2>&1 &
host_pid=$!
tries=0
while ! grep -q 'NET_READY host' "$host_log"; do
  if ! kill -0 "$host_pid" 2>/dev/null; then cat "$host_log"; exit 1; fi
  tries=$((tries + 1))
  if [ "$tries" -ge 30 ]; then cat "$host_log"; exit 1; fi
  sleep 1
done
"$GODOT_BIN" --headless --path . -- --net-join 127.0.0.1 "$@" >"$client_log" 2>&1 &
client_pid=$!
tries=0
while kill -0 "$host_pid" 2>/dev/null || kill -0 "$client_pid" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge 250 ]; then echo 'NET_TEST FAIL: process timeout'; tail -20 "$host_log" "$client_log"; exit 1; fi
  sleep 1
done
host_status=0
client_status=0
wait "$host_pid" || host_status=$?
wait "$client_pid" || client_status=$?
host_pid=
client_pid=
grep -E '^NET_(RESULTS|STATS|TEST)' "$host_log" "$client_log" || true
if [ "$host_status" -ne 0 ] || [ "$client_status" -ne 0 ]; then
  tail -25 "$host_log" "$client_log"
  exit 1
fi
for log in "$host_log" "$client_log"; do
  if ! grep -q '^NET_TEST PASS' "$log" || grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then tail -25 "$log"; exit 1; fi
done
echo "NET_TEST PASS: $host_log $client_log"

#!/bin/sh
# Dedicated-server acceptance (Phase 16): a headless dedicated server plus
# two automated AI-driven clients complete a 1-lap race, and the server
# loops back to an empty lobby afterward (SERVER_STATE LOBBY twice).
# Captures logs, bounds runtime, and reaps every child on success/failure/signal.
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
export HOME="$PROJECT_ROOT/.tmp-home"
LOG_DIR="$PROJECT_ROOT/.omc/phase16-logs"
mkdir -p "$LOG_DIR"
label=${NET_TEST_LABEL:-server}
server_log="$LOG_DIR/$label-server.log"
client1_log="$LOG_DIR/$label-client1.log"
client2_log="$LOG_DIR/$label-client2.log"
port=${NET_TEST_PORT:-24777}
server_pid=
client1_pid=
client2_pid=
cleanup() {
  for pid in "$client1_pid" "$client2_pid" "$server_pid"; do
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

"$GODOT_BIN" --headless --path . -- --server --port "$port" --laps 1 --ai 0 --max-players 8 >"$server_log" 2>&1 &
server_pid=$!
tries=0
while ! grep -q 'SERVER_READY' "$server_log"; do
  if ! kill -0 "$server_pid" 2>/dev/null; then cat "$server_log"; exit 1; fi
  tries=$((tries + 1))
  if [ "$tries" -ge 30 ]; then cat "$server_log"; exit 1; fi
  sleep 1
done

"$GODOT_BIN" --headless --path . -- --net-join 127.0.0.1 --net-port "$port" >"$client1_log" 2>&1 &
client1_pid=$!
"$GODOT_BIN" --headless --path . -- --net-join 127.0.0.1 --net-port "$port" >"$client2_log" 2>&1 &
client2_pid=$!

tries=0
while kill -0 "$client1_pid" 2>/dev/null || kill -0 "$client2_pid" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge 250 ]; then echo 'SERVER_TEST FAIL: client timeout'; tail -25 "$server_log" "$client1_log" "$client2_log"; exit 1; fi
  sleep 1
done
client1_status=0
client2_status=0
wait "$client1_pid" || client1_status=$?
wait "$client2_pid" || client2_status=$?
client1_pid=
client2_pid=

# Give the server a moment to observe RESULTS and loop back to lobby.
tries=0
while [ "$(grep -c 'SERVER_STATE LOBBY' "$server_log" 2>/dev/null || echo 0)" -lt 2 ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 20 ]; then break; fi
  sleep 1
done

kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=

grep -E '^(SERVER_STATE|SERVER_READY|NET_(RESULTS|STATS|TEST))' "$server_log" "$client1_log" "$client2_log" || true

fail=0
if [ "$client1_status" -ne 0 ] || [ "$client2_status" -ne 0 ]; then fail=1; fi
for log in "$client1_log" "$client2_log"; do
  if ! grep -q '^NET_TEST PASS' "$log" || grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then fail=1; fi
done
if [ "$(grep -c 'SERVER_STATE LOBBY' "$server_log")" -lt 2 ]; then fail=1; fi
if grep -qE 'SCRIPT ERROR|Parse Error' "$server_log"; then fail=1; fi

if [ "$fail" -ne 0 ]; then
  echo 'SERVER_TEST FAIL'
  tail -25 "$server_log" "$client1_log" "$client2_log"
  exit 1
fi
echo "SERVER_TEST PASS: $server_log $client1_log $client2_log"

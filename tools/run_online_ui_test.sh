#!/bin/sh
# Real-UI online acceptance harness (.omc/online_ui_brief.md): two full game
# processes drive the ACTUAL main menu -> ONLINE -> lobby -> HOST/JOIN ->
# ready -> race path via real button presses (scenes/test/online_ui_driver.gd),
# unlike tools/run_net_test.sh's --net-host/--net-join, which bypasses the
# lobby UI entirely. Self-caps at 240s and reaps both processes on every exit.
#
# usage:
#   tools/run_online_ui_test.sh                    # full race to results
#   tools/run_online_ui_test.sh --scenario wrong-password
#   tools/run_online_ui_test.sh --scenario host-leaves
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
export HOME="$PROJECT_ROOT/.tmp-home"

SCENARIO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scenario)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "--scenario requires a value" >&2; exit 2; fi
      SCENARIO=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

LOG_DIR="$PROJECT_ROOT/.omc/online-ui-logs"
mkdir -p "$LOG_DIR"
label=${ONLINE_UI_TEST_LABEL:-${SCENARIO:-default}}
port=${ONLINE_UI_TEST_PORT:-24990}
code_file="$LOG_DIR/$label-code.txt"
rm -f "$code_file"
host_log="$LOG_DIR/$label-host.log"
join_log="$LOG_DIR/$label-join.log"
host_pid=
join_pid=

cleanup() {
  # Kill only this run's own captured PIDs -- a name-matching pkill would
  # also reap other worktrees' concurrent online_ui_driver runs.
  if [ -n "$host_pid" ]; then kill "$host_pid" 2>/dev/null || true; wait "$host_pid" 2>/dev/null || true; fi
  if [ -n "$join_pid" ]; then kill "$join_pid" 2>/dev/null || true; wait "$join_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

scenario_args=""
if [ -n "$SCENARIO" ]; then scenario_args="--scenario $SCENARIO"; fi

"$GODOT_BIN" --headless --path . res://scenes/test/online_ui_driver.tscn -- \
  --role host --ip 127.0.0.1 --port "$port" --code-file "$code_file" $scenario_args \
  >"$host_log" 2>&1 &
host_pid=$!

tries=0
while [ ! -s "$code_file" ]; do
  if ! kill -0 "$host_pid" 2>/dev/null; then echo 'ONLINE_UI_TEST FAIL: host exited before writing code file'; cat "$host_log"; exit 1; fi
  tries=$((tries + 1))
  if [ "$tries" -ge 60 ]; then echo 'ONLINE_UI_TEST FAIL: host never wrote code file'; cat "$host_log"; exit 1; fi
  sleep 1
done

"$GODOT_BIN" --headless --path . res://scenes/test/online_ui_driver.tscn -- \
  --role join --ip 127.0.0.1 --port "$port" --code-file "$code_file" $scenario_args \
  >"$join_log" 2>&1 &
join_pid=$!

tries=0
while kill -0 "$host_pid" 2>/dev/null || kill -0 "$join_pid" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge 240 ]; then
    echo 'ONLINE_UI_TEST FAIL: process timeout'
    tail -30 "$host_log" "$join_log"
    exit 1
  fi
  sleep 1
done

host_status=0
join_status=0
wait "$host_pid" || host_status=$?
wait "$join_pid" || join_status=$?
host_pid=
join_pid=

grep -E '^ONLINE_UI' "$host_log" "$join_log" || true

if grep -qiE 'script error|parse error' "$host_log" "$join_log"; then
  echo 'ONLINE_UI_TEST FAIL: script/parse error in logs'
  tail -30 "$host_log" "$join_log"
  exit 1
fi

if [ -n "$SCENARIO" ]; then
  # wrong-password / host-leaves intentionally never reach RESULTS; success
  # means the join process bounced back with a captured rejection message,
  # and the host driver must still have exited cleanly.
  if [ "$host_status" -ne 0 ] || [ "$join_status" -ne 0 ]; then
    echo "ONLINE_UI_TEST FAIL: host_status=$host_status join_status=$join_status"
    tail -30 "$host_log" "$join_log"
    exit 1
  fi
  join_result=$(grep '^ONLINE_UI_RESULT' "$join_log" | tail -1)
  if [ -z "$join_result" ]; then
    echo 'ONLINE_UI_TEST FAIL: join produced no ONLINE_UI_RESULT'
    exit 1
  fi
  if echo "$join_result" | grep -qE '"errors"[[:space:]]*:[[:space:]]*\[\]'; then
    echo "ONLINE_UI_TEST FAIL: join reported no error text for scenario ($join_result)"
    exit 1
  fi
  if [ "$SCENARIO" = "wrong-password" ] && ! echo "$join_result" | grep -qiE 'password'; then
    echo "ONLINE_UI_TEST FAIL: join did not show the password-rejection reason ($join_result)"
    exit 1
  fi
  echo "$join_result"
  echo "ONLINE_UI_TEST PASS (scenario=$SCENARIO): $host_log $join_log"
  exit 0
fi

if [ "$host_status" -ne 0 ] || [ "$join_status" -ne 0 ]; then
  echo "ONLINE_UI_TEST FAIL: host_status=$host_status join_status=$join_status"
  tail -30 "$host_log" "$join_log"
  exit 1
fi

host_result=$(grep '^ONLINE_UI_RESULT' "$host_log" | tail -1)
join_result=$(grep '^ONLINE_UI_RESULT' "$join_log" | tail -1)
echo "$host_result"
echo "$join_result"

if ! echo "$host_result" | grep -qE '"reached_results"[[:space:]]*:[[:space:]]*true'; then
  echo 'ONLINE_UI_TEST FAIL: host did not reach results'
  exit 1
fi
if ! echo "$join_result" | grep -qE '"reached_results"[[:space:]]*:[[:space:]]*true'; then
  echo 'ONLINE_UI_TEST FAIL: join did not reach results'
  exit 1
fi

karts=$(echo "$host_result" | sed -n 's/.*"karts"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
if [ -z "$karts" ] || [ "$karts" -lt 2 ]; then
  echo "ONLINE_UI_TEST FAIL: karts=$karts < 2"
  exit 1
fi

echo "ONLINE_UI_TEST PASS: $host_log $join_log"

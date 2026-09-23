#!/bin/bash
# Windowed visual review: captures the same race frames on all four content
# tracks. usage: tools/showcase.sh <out_dir> [shot_times_csv]
set -u
OUT="${1:?usage: tools/showcase.sh <out_dir> [shot_times_csv]}"
TIMES="${2:-5,10,16}"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
cd "$(dirname "$0")/.."
status=0
for t in 0 1 2 3; do
  "$GODOT" --path . --resolution 1600x900 res://scenes/test/showcase_snapshot.tscn -- "$OUT/track_$t" "$t" "$TIMES" > "$OUT.track_$t.log" 2>&1 &
  pid=$!
  ( sleep 120; kill "$pid" 2>/dev/null ) &
  watchdog=$!
  wait "$pid" || status=1
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  n=$(ls "$OUT/track_$t"/*.png 2>/dev/null | wc -l | tr -d ' ')
  echo "track_$t shots=$n"
  [ "$n" -gt 0 ] || status=1
done
exit $status

#!/bin/sh
# Automatic merge gate (MODEL_OPERATING_RULES §6). Run by the merge-gate hook before any merge.
# Every check must pass; never relax a check to get a merge through.
set -u
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
cd "$PROJECT_ROOT"
fail=0
step() { printf '\n== %s\n' "$1"; }

step "parse"
if "$GODOT_BIN" --headless --path . --quit 2>&1 | grep -qiE 'script error|parse error'; then echo "FAIL: script/parse errors"; fail=1; else echo "ok"; fi

step "tests"
out=$(tools/run_tests.sh 2>&1); echo "$out" | grep -E '^(Tests|Passing Tests|Failing)' 
if ! echo "$out" | grep -qE '^Passing Tests'; then echo "FAIL: test run did not complete"; fail=1
elif [ "$(echo "$out" | awk '/^Tests/{t=$2} /^Passing Tests/{p=$3} END{print (t==p && t>0)?"eq":"ne"}')" != "eq" ]; then echo "FAIL: failing tests"; fail=1; else echo "ok"; fi

step "tracks"
if tools/validate_tracks.sh 2>&1 | grep -q 'FAILED'; then echo "FAIL: track validation"; fail=1; else echo "ok"; fi

step "sim smoke"
if [ -x tools/run_sim.sh ]; then
  if tools/run_sim.sh --races 1 --karts 8 --laps 1 2>/dev/null | grep -q '"success":true'; then echo "ok"; else echo "FAIL: sim smoke race"; fail=1; fi
fi

step "file size (.gd <= 400 lines)"
big=$(find . -name '*.gd' -not -path './addons/*' -not -path './.godot/*' | xargs wc -l | awk '$1>400 && $2!="total"{print}')
if [ -n "$big" ]; then echo "FAIL:"; echo "$big"; fail=1; else echo "ok"; fi

step "project.godot hygiene"
if grep -q 'certificate_bundle_override' project.godot; then echo "FAIL: TLS override present"; fail=1; else echo "ok"; fi

step "sensitive paths (manual approval required if changed vs main)"
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  changed=$(git diff --name-only origin/main...HEAD 2>/dev/null | grep -E '^(net/|kart/kart_physics\.gd|race/lap_tracker\.gd|race/position_tracker\.gd|core/autoload/save_manager\.gd)' || true)
  if [ -n "$changed" ]; then echo "NOTE: sensitive paths changed — do not auto-merge without explicit approval:"; echo "$changed"; [ "${GATE_ALLOW_SENSITIVE:-0}" = "1" ] || fail=1; else echo "ok"; fi
fi

printf '\n== RESULT: %s\n' "$([ $fail -eq 0 ] && echo PASS || echo FAIL)"
exit $fail

#!/bin/sh
# Automatic merge gate (MODEL_OPERATING_RULES §6). Run by the merge-gate hook before any merge.
# Every check must pass; never relax a check to get a merge through.
set -u
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}
cd "$PROJECT_ROOT"
fail=0
gate_tmp=$(mktemp -d "${TMPDIR:-/tmp}/turbo-circuit-gate.XXXXXX")
cleanup() { rm -rf "$gate_tmp"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
step() { printf '\n== %s\n' "$1"; }
# A failing stage must leave evidence behind: the temp dir is wiped on exit, so copy the
# failing log somewhere stable and show its tail instead of only printing an exit status.
keep_stage_log() {
  mkdir -p "$PROJECT_ROOT/.omc/gate-logs"
  kept="$PROJECT_ROOT/.omc/gate-logs/$1.log"
  cp "$2" "$kept" 2>/dev/null || true
  echo "--- last 30 lines ($kept)"
  tail -30 "$2" 2>/dev/null || true
  echo "---"
}
run_stage() {
  stage_name=$1
  expected_output=$2
  shift 2
  stage_log="$gate_tmp/$stage_name.log"
  "$@" >"$stage_log" 2>&1
  stage_status=$?
  if [ "$stage_status" -ne 0 ]; then
    echo "FAIL: $stage_name exited with status $stage_status"
    keep_stage_log "$stage_name" "$stage_log"
    fail=1
    return 1
  fi
  if ! grep -qE -- "$expected_output" "$stage_log"; then
    echo "FAIL: $stage_name missing completion marker"
    keep_stage_log "$stage_name" "$stage_log"
    fail=1
    return 1
  fi
  return 0
}

step "import (fresh checkouts need the class cache)"
if run_stage import '^Godot Engine v' "$GODOT_BIN" --headless --path . --import; then echo "ok"; fi

step "parse"
if run_stage parse '^Godot Engine v' "$GODOT_BIN" --headless --path . --quit; then
  if grep -qiE 'script error|parse error' "$gate_tmp/parse.log"; then echo "FAIL: parse reported script/parse errors"; grep -iE 'script error|parse error' "$gate_tmp/parse.log" | head -10; keep_stage_log parse "$gate_tmp/parse.log"; fail=1; else echo "ok"; fi
fi

step "tests"
if run_stage tests '---- All tests passed! ----' tools/run_tests.sh; then
  grep -E '^(Tests|Passing Tests|Failing)' "$gate_tmp/tests.log" || true
  if [ "$(awk '/^Tests/{t=$2} /^Passing Tests/{p=$3} END{print (t==p && t>0)?"eq":"ne"}' "$gate_tmp/tests.log")" != "eq" ]; then echo "FAIL: tests completion totals do not match"; awk '/res:\/\/tests\/.*\.gd/{f=$0} /\[Failed\]/{print f}' "$gate_tmp/tests.log" | sort | uniq -c | head -5; keep_stage_log tests "$gate_tmp/tests.log"; fail=1; else echo "ok"; fi
fi

step "tracks"
if run_stage tracks '^TRACK VALIDATION PASSED:' tools/validate_tracks.sh; then echo "ok"; fi

step "sim smoke"
if [ -x tools/run_sim.sh ]; then
  if run_stage sim '"success":true' tools/run_sim.sh --races 1 --karts 8 --laps 1; then echo "ok"; fi
else
  echo "FAIL: tools/run_sim.sh missing or not executable"; fail=1
fi

step "file size (.gd <= 400 lines)"
big=$(find . -name '*.gd' -not -path './addons/*' -not -path './.godot/*' | xargs wc -l | awk '$1>400 && $2!="total"{print}')
if [ -n "$big" ]; then echo "FAIL:"; echo "$big"; fail=1; else echo "ok"; fi

step "project.godot hygiene"
if grep -q 'certificate_bundle_override' project.godot; then echo "FAIL: TLS override present"; fail=1; else echo "ok"; fi

step "sensitive paths (manual approval required if changed vs main)"
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  changed=$(git diff --name-only origin/main...HEAD 2>/dev/null | grep -E '^(net/|kart/kart_physics\.gd|race/lap_tracker\.gd|race/position_tracker\.gd|core/autoload/save_manager\.gd)' || true)
  if [ -n "$changed" ]; then
    echo "NOTE: sensitive paths changed — requires two independent cross-reviews:"; echo "$changed"
    # Approval record: .omc/sensitive_approval.md must name the reviewed commit (HEAD~0 or the pre-fix HEAD) and both reviews.
    head_sha=$(git rev-parse --short=7 HEAD)
    if [ "${GATE_ALLOW_SENSITIVE:-0}" = "1" ]; then echo "approved via GATE_ALLOW_SENSITIVE"
    elif [ -f .omc/sensitive_approval.md ] && grep -q "$head_sha" .omc/sensitive_approval.md && grep -qi "review-1" .omc/sensitive_approval.md && grep -qi "review-2" .omc/sensitive_approval.md; then
      echo "approved via .omc/sensitive_approval.md (two reviews recorded for $head_sha)"
    else echo "FAIL: sensitive paths lack two recorded cross-reviews for $head_sha"; fail=1; fi
  else echo "ok"; fi
else
  echo "FAIL: cannot resolve origin/main to check sensitive paths"; fail=1
fi

printf '\n== RESULT: %s\n' "$([ $fail -eq 0 ] && echo PASS || echo FAIL)"
exit $fail

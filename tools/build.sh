#!/bin/sh
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-godot}
cd "$PROJECT_ROOT"
VERSION=$("$GODOT_BIN" --version)
TEMPLATE_VERSION=$(printf '%s' "$VERSION" | cut -d. -f1-3)
case "$(uname -s)" in
  Darwin) TEMPLATE_ROOT="$HOME/Library/Application Support/Godot/export_templates" ;;
  *) TEMPLATE_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates" ;;
esac
TEMPLATE_DIR="$TEMPLATE_ROOT/$TEMPLATE_VERSION"
ARCHIVE_VERSION=$(printf '%s' "$TEMPLATE_VERSION" | sed 's/\.stable$/-stable/')
for template in windows_release_x86_64.exe macos.zip linux_release.x86_64; do
  if [ ! -f "$TEMPLATE_DIR/$template" ]; then
    printf 'Missing Godot %s export template: %s\n' "$VERSION" "$TEMPLATE_DIR/$template" >&2
    printf 'Install an already obtained matching official TPZ (no automatic download):\n' >&2
    printf 'mkdir -p "%s" && unzip -j "/path/to/Godot_v%s_export_templates.tpz" "templates/*" -d "%s"\n' "$TEMPLATE_DIR" "$ARCHIVE_VERSION" "$TEMPLATE_DIR" >&2
    exit 2
  fi
done
mkdir -p build/windows build/macos build/linux
"$GODOT_BIN" --headless --path . --export-release 'Windows x86_64' build/windows/TurboCircuit.exe
"$GODOT_BIN" --headless --path . --export-release 'macOS Universal' build/macos/TurboCircuit.zip
"$GODOT_BIN" --headless --path . --export-release 'Linux x86_64' build/linux/TurboCircuit.x86_64

# The Linux export drops a loose binary + .pck; zip transport (and some CI artifact
# upload paths) doesn't reliably preserve the executable bit, so make it explicit
# before packaging. Keep the loose files in place alongside the tarball.
chmod +x build/linux/TurboCircuit.x86_64
( cd build/linux && tar czf TurboCircuit-linux.tar.gz TurboCircuit.x86_64 TurboCircuit.pck )

print_artifact() {
  if [ ! -f "$1" ]; then
    printf 'ARTIFACT MISSING: %s\n' "$1" >&2
    exit 1
  fi
  size=$(wc -c < "$1" | tr -d ' ')
  printf 'ARTIFACT %s (%s bytes)\n' "$1" "$size"
}
print_artifact build/windows/TurboCircuit.exe
print_artifact build/macos/TurboCircuit.zip
print_artifact build/linux/TurboCircuit.x86_64
print_artifact build/linux/TurboCircuit.pck
print_artifact build/linux/TurboCircuit-linux.tar.gz

# Host-platform smoke run: exercises the paths that only break after export (data
# scanning through .tres.remap files, track instancing — see scenes/export_selftest.gd).
# Only macOS is runnable directly on this dev machine; Windows/Linux builds still need a
# smoke run on real hardware (see docs/RELEASE.md).
if [ "$(uname -s)" = "Darwin" ]; then
  rm -rf build/macos/extracted
  mkdir -p build/macos/extracted
  unzip -q build/macos/TurboCircuit.zip -d build/macos/extracted
  app_count=$(find build/macos/extracted -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')
  if [ "$app_count" != "1" ]; then
    echo "SELFTEST FAIL: expected exactly one .app in build/macos/extracted, found $app_count" >&2
    exit 1
  fi
  app_dir=$(find build/macos/extracted -maxdepth 1 -name '*.app')
  bin_count=$(find "$app_dir/Contents/MacOS" -maxdepth 1 -type f | wc -l | tr -d ' ')
  if [ "$bin_count" != "1" ]; then
    echo "SELFTEST FAIL: expected exactly one file in $app_dir/Contents/MacOS, found $bin_count" >&2
    exit 1
  fi
  app_bin=$(find "$app_dir/Contents/MacOS" -maxdepth 1 -type f)
  chmod +x "$app_bin"
  selftest_log=$(mktemp "${TMPDIR:-/tmp}/turbocircuit-selftest.XXXXXX")
  "$app_bin" --headless -- --selftest >"$selftest_log" 2>&1 || true
  selftest_line=$(grep '^EXPORT_SELFTEST ' "$selftest_log" || true)
  if [ -z "$selftest_line" ]; then
    echo "SELFTEST FAIL: no EXPORT_SELFTEST line in output" >&2
    cat "$selftest_log" >&2
    rm -f "$selftest_log"
    exit 1
  fi
  printf '%s\n' "$selftest_line"
  if ! printf '%s' "$selftest_line" | grep -q '"passed":true'; then
    echo "SELFTEST FAIL: EXPORT_SELFTEST reported passed:true missing" >&2
    rm -f "$selftest_log"
    exit 1
  fi
  rm -f "$selftest_log"
  echo "SELFTEST PASS (macOS)"
else
  echo "SELFTEST SKIPPED: host platform $(uname -s) has no --selftest runner in this script yet"
fi

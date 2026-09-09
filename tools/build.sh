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

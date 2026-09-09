#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-/opt/homebrew/bin/godot}

cd "$PROJECT_ROOT"
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/test_loop/test_loop.tscn
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/test_loop_hills/test_loop_hills.tscn
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/test_hairpin/test_hairpin.tscn
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/track_02_lumen_underpass/track_02_lumen_underpass.tscn
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/track_03_glacier_crown/track_03_glacier_crown.tscn
"$GODOT_BIN" --headless --path . -s track/track_validator.gd -- \
	res://track/tracks/track_04_ochre_rift/track_04_ochre_rift.tscn

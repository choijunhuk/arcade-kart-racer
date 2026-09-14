extends SceneTree

## Headless tuning-evidence summary (Phase 18d-3): aggregates every `*.json`
## telemetry file in `<dir>` and prints drift-release tier ratios, mean/median
## hit recovery, and mean wall impacts per lap.
##
## Usage: godot --headless --path . -s tools/telemetry_summary.gd -- <dir>

const TIER_KEYS: PackedStringArray = ["0", "1", "2", "3"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		print("Usage: telemetry_summary.gd <dir>")
		quit(1)
		return
	var directory: String = arguments[0]
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		print("Could not open directory: %s" % directory)
		quit(1)
		return
	var laps: Array = []
	var files_read: int = 0
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(entry)))
			if value is Dictionary and value.get("laps") is Array:
				laps.append_array(value["laps"])
				files_read += 1
		entry = dir.get_next()
	dir.list_dir_end()
	if laps.is_empty():
		print("No telemetry laps found in %s (%d files read)." % [directory, files_read])
		quit(0)
		return
	_print_summary(laps, files_read)
	quit(0)


func _print_summary(laps: Array, files_read: int) -> void:
	var tier_counts: Dictionary = {"0": 0, "1": 0, "2": 0, "3": 0}
	var recovery_seconds: Array[float] = []
	var wall_impacts_total: int = 0
	for entry: Variant in laps:
		if not entry is Dictionary:
			continue
		var lap: Dictionary = entry
		var tiers: Dictionary = lap.get("drift_release_tiers", {})
		for key: String in TIER_KEYS:
			tier_counts[key] = int(tier_counts[key]) + int(tiers.get(key, 0))
		for seconds: Variant in lap.get("hit_recovery_seconds", []):
			recovery_seconds.append(float(seconds))
		wall_impacts_total += int(lap.get("wall_impacts", 0))
	var total_releases: int = 0
	for key: String in TIER_KEYS:
		total_releases += int(tier_counts[key])
	print("Telemetry summary: %d files, %d laps" % [files_read, laps.size()])
	print("Drift release tiers:")
	for key: String in TIER_KEYS:
		var count: int = int(tier_counts[key])
		var ratio: float = float(count) / float(total_releases) if total_releases > 0 else 0.0
		print("  tier %s: %d (%.1f%%)" % [key, count, ratio * 100.0])
	if recovery_seconds.is_empty():
		print("Hit recovery: no hits recorded")
	else:
		print("Hit recovery: mean %.2fs, median %.2fs (n=%d)" % [_mean(recovery_seconds), _median(recovery_seconds), recovery_seconds.size()])
	print("Wall impacts per lap: mean %.2f" % (float(wall_impacts_total) / float(laps.size())))


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _median(values: Array[float]) -> float:
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var count: int = sorted_values.size()
	var middle: int = count / 2
	if count % 2 == 1:
		return sorted_values[middle]
	return (sorted_values[middle - 1] + sorted_values[middle]) / 2.0

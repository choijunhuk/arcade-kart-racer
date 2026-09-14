class_name TelemetryFileRotation
extends RefCounted

## File-naming/rotation helpers for RaceTelemetryService (18d-4 review fix
## #4), split out of core/autoload/race_telemetry.gd to keep that autoload
## under the 400-line budget. Only DirAccess/FileAccess existence checks —
## no EventBus or scene-tree access — so these stay testable without a
## scene tree.


## Returns `filename` unchanged if free in `directory`, otherwise the first
## `<stem>-N.<ext>` (N starting at 2) that does not already exist, trying up
## to `max_suffix` suffixes. Returns an empty string once every suffix up to
## `max_suffix` is taken, so the caller can skip the write instead of
## clobbering the last candidate checked (18d-4 review fix #3).
static func resolve_collision_free_filename(directory: String, filename: String, max_suffix: int) -> String:
	if not FileAccess.file_exists(directory.path_join(filename)):
		return filename
	var stem: String = filename.get_basename()
	var extension: String = filename.get_extension()
	for suffix: int in range(2, max_suffix + 2):
		var candidate: String = "%s-%d.%s" % [stem, suffix, extension]
		if not FileAccess.file_exists(directory.path_join(candidate)):
			return candidate
	return ""


## Deletes files belonging to the oldest races beyond `keep` races (18d-4
## review fix #4), not merely the oldest files: a race's files (one per
## recorded local human kart) share one "<stamp>-<track_id>" race-group key
## and must be rotated out together, or a single newer race would evict an
## older race's files one player at a time instead of whole races at once.
static func rotate(directory: String, keep: int) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return
	var files: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	var race_groups: PackedStringArray = PackedStringArray()
	var group_by_file: Dictionary = {}
	for file_name: String in files:
		var group: String = race_group_key(file_name)
		group_by_file[file_name] = group
		if race_groups.is_empty() or race_groups[race_groups.size() - 1] != group:
			race_groups.append(group)
	var evict_count: int = maxi(0, race_groups.size() - keep)
	if evict_count == 0:
		return
	var groups_to_evict: Dictionary = {}
	for i: int in range(evict_count):
		groups_to_evict[race_groups[i]] = true
	for file_name: String in files:
		if groups_to_evict.has(group_by_file[file_name]):
			dir.remove(file_name)


## Returns the race-group key `filename` belongs to: everything before the
## trailing "-p<N>.json" or "-p<N>-<suffix>.json" (18d-4 review fix #3's
## collision suffix). Filenames that don't match this player-file naming
## (e.g. legacy or test fixture names) are their own single-file group,
## matching the pre-fix-#4 one-file-per-group rotation behavior.
static func race_group_key(filename: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("^(.*)-p\\d+(?:-\\d+)?\\.json$")
	var result: RegExMatch = regex.search(filename)
	return result.get_string(1) if result != null else filename

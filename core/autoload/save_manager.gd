class_name SaveManagerService
extends Node

const CURRENT_VERSION: int = 2
const DEFAULT_SAVE_PATH: String = "user://save.json"
const BACKUP_SUFFIX: String = ".bak"
const PLAYER_PROFILE_COUNT: int = 4

var save_path: String = DEFAULT_SAVE_PATH


func _init(custom_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = custom_save_path


## Returns a fresh save payload with every key required by the current version.
func default_data() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"best_laps": {},
		"best_positions": {},
		"grand_prix_bests": {},
		"player_profiles": _default_player_profiles(),
		"last_selection": {"driver": "", "kart": "medium", "track": "test_loop"},
		"unlocks": [],
	}


## Loads the primary save, recovering the backup or defaults when necessary.
func load_data() -> Dictionary:
	var primary: Dictionary = _read_valid_data(save_path)
	if not primary.is_empty():
		return _migrate(primary)

	var backup_path: String = save_path + BACKUP_SUFFIX
	var backup: Dictionary = _read_valid_data(backup_path)
	if not backup.is_empty():
		var recovered: Dictionary = _migrate(backup)
		_write_json(save_path, recovered)
		return recovered

	var defaults: Dictionary = default_data()
	_write_json(save_path, defaults)
	return defaults


## Writes versioned data and preserves the last valid primary as a backup.
func save_data(data: Dictionary) -> Error:
	var normalized: Dictionary = _migrate(data)
	normalized["version"] = CURRENT_VERSION
	var previous: Dictionary = _read_valid_data(save_path)
	if not previous.is_empty():
		var backup_error: Error = _write_json(save_path + BACKUP_SUFFIX, previous)
		if backup_error != OK:
			return backup_error
	return _write_json(save_path, normalized)


## Records a track result, retaining only lower positive lap times/positions.
func record_race_result(track_id: StringName, best_lap_ms: int, position: int) -> Error:
	return record_player_race_result(0, track_id, best_lap_ms, position)


## Records one P1-P4 profile result without overwriting another local player.
func record_player_race_result(
	profile_index: int, track_id: StringName, best_lap_ms: int, position: int,
) -> Error:
	if profile_index < 0 or profile_index >= PLAYER_PROFILE_COUNT:
		return ERR_INVALID_PARAMETER
	var data: Dictionary = load_data()
	var track_key: String = String(track_id)
	var profiles: Dictionary = data.get("player_profiles", _default_player_profiles()) as Dictionary
	var profile_key: String = _profile_key(profile_index)
	var profile: Dictionary = profiles.get(profile_key, {"best_laps": {}, "best_positions": {}}) as Dictionary
	var best_laps: Dictionary = profile.get("best_laps", {}) as Dictionary
	var best_positions: Dictionary = profile.get("best_positions", {}) as Dictionary
	if best_lap_ms > 0 and (not best_laps.has(track_key) or best_lap_ms < int(best_laps[track_key])):
		best_laps[track_key] = best_lap_ms
	if position > 0 and (not best_positions.has(track_key) or position < int(best_positions[track_key])):
		best_positions[track_key] = position
	profile["best_laps"] = best_laps
	profile["best_positions"] = best_positions
	profiles[profile_key] = profile
	data["player_profiles"] = profiles
	if profile_index == 0:
		(data["best_laps"] as Dictionary).merge(best_laps, true)
		(data["best_positions"] as Dictionary).merge(best_positions, true)
	return save_data(data)


## Returns the saved best lap in milliseconds, or -1 when no record exists.
func get_best_lap_ms(track_id: StringName) -> int:
	var data: Dictionary = load_data()
	var best_laps: Dictionary = data.get("best_laps", {}) as Dictionary
	return int(best_laps.get(String(track_id), -1))


## Returns a P1-P4 profile best lap in milliseconds, or -1.
func get_player_best_lap_ms(profile_index: int, track_id: StringName) -> int:
	if profile_index < 0 or profile_index >= PLAYER_PROFILE_COUNT:
		return -1
	var data: Dictionary = load_data()
	var profiles: Dictionary = data.get("player_profiles", {}) as Dictionary
	var profile: Dictionary = profiles.get(_profile_key(profile_index), {}) as Dictionary
	var best_laps: Dictionary = profile.get("best_laps", {}) as Dictionary
	return int(best_laps.get(String(track_id), -1))


## Retains the player's best cup rank and highest score, separated by difficulty.
func record_grand_prix(cup_key: StringName, position: int, points: int) -> Error:
	if position <= 0 or points < 0:
		return ERR_INVALID_PARAMETER
	var data: Dictionary = load_data()
	var bests: Dictionary = data["grand_prix_bests"]
	var key: String = String(cup_key)
	var previous: Dictionary = bests.get(key, {})
	bests[key] = {
		"position": mini(position, int(previous.get("position", position))),
		"points": maxi(points, int(previous.get("points", 0))),
	}
	return save_data(data)


## Persists the three content identifiers used to start the latest race.
func save_last_selection(driver_id: StringName, kart_id: StringName, track_id: StringName) -> Error:
	var data: Dictionary = load_data()
	data["last_selection"] = {
		"driver": String(driver_id),
		"kart": String(kart_id),
		"track": String(track_id),
	}
	return save_data(data)


func _read_valid_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed as Dictionary
	var version_value: Variant = data.get("version", -1)
	if not version_value is int and not version_value is float:
		return {}
	var version: int = int(version_value)
	if not is_equal_approx(float(version), float(version_value)):
		return {}
	if version < 0 or version > CURRENT_VERSION:
		return {}
	# Syntactically valid JSON can still violate the types consumed by menus/results.
	for key: String in ["best_laps", "best_positions", "last_selection", "grand_prix_bests", "player_profiles"]:
		if data.has(key) and not data[key] is Dictionary:
			return {}
	for key: String in ["best_laps", "best_positions"]:
		var records: Dictionary = data.get(key, {})
		for value: Variant in records.values():
			if not (value is int or value is float):
				return {}
			if not is_finite(float(value)) or float(value) <= 0.0:
				return {}
	var selection: Dictionary = data.get("last_selection", {})
	var gp_bests: Dictionary = data.get("grand_prix_bests", {})
	var profiles: Dictionary = data.get("player_profiles", {})
	for profile: Variant in profiles.values():
		if not profile is Dictionary:
			return {}
		for section: String in ["best_laps", "best_positions"]:
			if not (profile as Dictionary).get(section, {}) is Dictionary:
				return {}
	for record: Variant in gp_bests.values():
		if not record is Dictionary:
			return {}
		for key: String in ["position", "points"]:
			var value: Variant = record.get(key)
			if not (value is int or value is float) or not is_finite(float(value)):
				return {}
			if float(value) < (1.0 if key == "position" else 0.0) or float(value) != floorf(float(value)):
				return {}
	for value: Variant in selection.values():
		if not value is String:
			return {}
	if data.has("unlocks") and not data["unlocks"] is Array:
		return {}
	return data


func _migrate(data: Dictionary) -> Dictionary:
	var migrated: Dictionary = data.duplicate(true)
	var version: int = int(migrated.get("version", 0))
	while version < CURRENT_VERSION:
		match version:
			0:
				migrated = _migrate_v0_to_v1(migrated)
			1:
				migrated = _migrate_v1_to_v2(migrated)
			_:
				push_error("No save migration registered for version %d" % version)
				return default_data()
		version = int(migrated.get("version", version + 1))
	return _merge_with_defaults(migrated)


func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var migrated: Dictionary = _merge_with_defaults(data)
	migrated["version"] = 1
	return migrated


func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var migrated: Dictionary = _merge_with_defaults(data)
	var profiles: Dictionary = migrated["player_profiles"]
	var primary: Dictionary = profiles.get("P1", {"best_laps": {}, "best_positions": {}})
	for section: String in ["best_laps", "best_positions"]:
		var legacy: Dictionary = migrated[section]
		var records: Dictionary = primary.get(section, {})
		for track: Variant in legacy:
			records[track] = mini(int(records.get(track, legacy[track])), int(legacy[track]))
		primary[section] = records
		legacy.merge(records, true)
	profiles["P1"] = primary
	migrated["version"] = 2
	return migrated


func _merge_with_defaults(data: Dictionary) -> Dictionary:
	var merged: Dictionary = default_data()
	for key: Variant in data:
		merged[key] = data[key]
	return merged


func _default_player_profiles() -> Dictionary:
	var profiles: Dictionary = {}
	for index: int in range(PLAYER_PROFILE_COUNT):
		profiles[_profile_key(index)] = {"best_laps": {}, "best_positions": {}}
	return profiles


func _profile_key(profile_index: int) -> String:
	return "P%d" % (profile_index + 1)


func _write_json(path: String, data: Dictionary) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK

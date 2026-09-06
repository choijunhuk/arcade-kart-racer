class_name SaveManagerService
extends Node

const CURRENT_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://save.json"
const BACKUP_SUFFIX: String = ".bak"

var save_path: String = DEFAULT_SAVE_PATH


func _init(custom_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = custom_save_path


## Returns a fresh save payload with every key required by version 1.
func default_data() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"best_laps": {},
		"best_positions": {},
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
	var normalized: Dictionary = _merge_with_defaults(data)
	normalized["version"] = CURRENT_VERSION
	var previous: Dictionary = _read_valid_data(save_path)
	if not previous.is_empty():
		var backup_error: Error = _write_json(save_path + BACKUP_SUFFIX, previous)
		if backup_error != OK:
			return backup_error
	return _write_json(save_path, normalized)


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
	return data


func _migrate(data: Dictionary) -> Dictionary:
	var migrated: Dictionary = data.duplicate(true)
	var version: int = int(migrated.get("version", 0))
	while version < CURRENT_VERSION:
		match version:
			0:
				migrated = _migrate_v0_to_v1(migrated)
			_:
				push_error("No save migration registered for version %d" % version)
				return default_data()
		version = int(migrated.get("version", version + 1))
	return _merge_with_defaults(migrated)


func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var migrated: Dictionary = _merge_with_defaults(data)
	migrated["version"] = 1
	return migrated


func _merge_with_defaults(data: Dictionary) -> Dictionary:
	var merged: Dictionary = default_data()
	for key: Variant in data:
		merged[key] = data[key]
	return merged


func _write_json(path: String, data: Dictionary) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK

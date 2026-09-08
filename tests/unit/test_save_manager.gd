extends GutTest

const SAVE_PATH: String = "user://phase0_save_manager_test.json"
const BACKUP_PATH: String = SAVE_PATH + ".bak"


func before_each() -> void:
	_remove_test_files()


func after_each() -> void:
	_remove_test_files()


func test_default_save_contains_current_version_and_required_sections() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(manager)

	var data: Dictionary = manager.load_data()

	assert_eq(data.get("version"), SaveManagerService.CURRENT_VERSION)
	assert_true(data.has("best_laps"))
	assert_true(data.has("best_positions"))
	assert_true(data.has("last_selection"))
	assert_true(data.has("unlocks"))


func test_corrupt_primary_recovers_valid_backup_and_restores_primary() -> void:
	_write_text(SAVE_PATH, "{ definitely not json")
	var backup_data: Dictionary = {
		"version": SaveManagerService.CURRENT_VERSION,
		"best_laps": {"test_loop": 65432},
		"best_positions": {},
		"last_selection": {"driver": "", "kart": "medium", "track": "test_loop"},
		"unlocks": [],
	}
	_write_text(BACKUP_PATH, JSON.stringify(backup_data))
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(manager)

	var recovered: Dictionary = manager.load_data()
	var restored_text: String = FileAccess.get_file_as_string(SAVE_PATH)
	var restored: Variant = JSON.parse_string(restored_text)

	assert_eq(int(recovered["best_laps"]["test_loop"]), 65432)
	assert_true(restored is Dictionary)
	assert_eq(int((restored as Dictionary)["version"]), SaveManagerService.CURRENT_VERSION)


func test_record_race_result_only_replaces_bests_with_better_values() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(manager)
	assert_true(manager.has_method("record_race_result"))
	if not manager.has_method("record_race_result"):
		return
	assert_eq(manager.call("record_race_result", &"test_loop", 12000, 3), OK)
	assert_eq(manager.call("record_race_result", &"test_loop", 14000, 5), OK)
	var unchanged: Dictionary = manager.load_data()
	assert_eq(int(unchanged["best_laps"]["test_loop"]), 12000)
	assert_eq(int(unchanged["best_positions"]["test_loop"]), 3)

	assert_eq(manager.call("record_race_result", &"test_loop", 11000, 2), OK)
	var improved: Dictionary = manager.load_data()
	assert_eq(int(improved["best_laps"]["test_loop"]), 11000)
	assert_eq(int(improved["best_positions"]["test_loop"]), 2)


func test_best_lap_lookup_returns_saved_milliseconds_or_negative_one() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(manager)
	assert_true(manager.has_method("get_best_lap_ms"))
	if not manager.has_method("get_best_lap_ms"):
		return
	assert_eq(int(manager.call("get_best_lap_ms", &"test_loop")), -1)
	assert_eq(manager.record_race_result(&"test_loop", 12_345, 2), OK)

	assert_eq(int(manager.call("get_best_lap_ms", &"test_loop")), 12_345)


func test_last_selection_round_trip_persists_all_three_content_ids() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(manager)
	assert_true(manager.has_method("save_last_selection"))
	if not manager.has_method("save_last_selection"):
		return

	assert_eq(manager.call("save_last_selection", &"aurora_vale", &"medium", &"track_01_ridgeline_circuit"), OK)

	var reloaded: Dictionary = manager.load_data()
	assert_eq(reloaded["last_selection"]["driver"], "aurora_vale")
	assert_eq(reloaded["last_selection"]["kart"], "medium")
	assert_eq(reloaded["last_selection"]["track"], "track_01_ridgeline_circuit")


func _write_text(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(contents)
	file.close()


func _remove_test_files() -> void:
	for path: String in [SAVE_PATH, BACKUP_PATH]:
		var absolute_path: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute_path)

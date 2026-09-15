extends GutTest

const SAVE_PATH: String = "user://phase0_save_manager_test.json"
const BACKUP_PATH: String = SAVE_PATH + ".bak"
const GHOST_DIRECTORY: String = "user://phase19-save-manager-ghosts"
const RESET_TRACK_ID: String = "track_02_lumen_underpass"


func before_each() -> void:
	_remove_test_files()
	_remove_ghost_fixtures()


func after_each() -> void:
	_remove_test_files()
	_remove_ghost_fixtures()


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


func test_corrupt_profile_records_recover_the_valid_backup() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(manager)
	var primary: Dictionary = manager.default_data()
	primary["player_profiles"]["P2"]["best_laps"] = {"test_loop": -10}
	primary["player_profiles"]["P3"]["best_positions"] = {"test_loop": "first"}
	var backup: Dictionary = manager.default_data()
	backup["player_profiles"]["P2"]["best_laps"] = {"test_loop": 54_321}
	_write_text(SAVE_PATH, JSON.stringify(primary))
	_write_text(BACKUP_PATH, JSON.stringify(backup))

	var recovered: Dictionary = manager.load_data()
	var restored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) as Dictionary

	assert_eq(int(recovered["player_profiles"]["P2"]["best_laps"]["test_loop"]), 54_321)
	assert_eq(restored, recovered)


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


func test_v2_to_v3_migration_drops_track_02_but_keeps_every_other_track() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	var other_tracks: Dictionary = {
		"track_01_ridgeline_circuit": 71_000,
		RESET_TRACK_ID: 65_000,
		"track_03_glacier_crown": 80_000,
		"track_04_ochre_rift": 90_000,
	}
	var v2_save: Dictionary = {
		"version": 2,
		"best_laps": other_tracks.duplicate(true),
		"best_positions": {"track_01_ridgeline_circuit": 1, RESET_TRACK_ID: 2, "track_03_glacier_crown": 3, "track_04_ochre_rift": 4},
		"grand_prix_bests": {},
		"last_selection": {"driver": "", "kart": "medium", "track": "test_loop"},
		"unlocks": [],
		"player_profiles": {
			"P1": {"best_laps": other_tracks.duplicate(true), "best_positions": {RESET_TRACK_ID: 2, "track_01_ridgeline_circuit": 1}},
			"P2": {"best_laps": {RESET_TRACK_ID: 61_000, "track_04_ochre_rift": 95_000}, "best_positions": {RESET_TRACK_ID: 1}},
			"P3": {"best_laps": {}, "best_positions": {}},
			"P4": {"best_laps": {}, "best_positions": {}},
		},
	}
	_write_text(SAVE_PATH, JSON.stringify(v2_save))

	var migrated: Dictionary = manager.load_data()

	assert_eq(int(migrated["version"]), 3)
	assert_false((migrated["best_laps"] as Dictionary).has(RESET_TRACK_ID))
	assert_false((migrated["best_positions"] as Dictionary).has(RESET_TRACK_ID))
	for track: String in ["track_01_ridgeline_circuit", "track_03_glacier_crown", "track_04_ochre_rift"]:
		assert_eq(int(migrated["best_laps"][track]), int(other_tracks[track]))
	assert_eq(int(migrated["best_positions"]["track_01_ridgeline_circuit"]), 1)
	assert_eq(int(migrated["best_positions"]["track_03_glacier_crown"]), 3)
	assert_eq(int(migrated["best_positions"]["track_04_ochre_rift"]), 4)

	var p1: Dictionary = migrated["player_profiles"]["P1"]
	assert_false((p1["best_laps"] as Dictionary).has(RESET_TRACK_ID))
	assert_false((p1["best_positions"] as Dictionary).has(RESET_TRACK_ID))
	assert_eq(int(p1["best_laps"]["track_01_ridgeline_circuit"]), 71_000)
	assert_eq(int(p1["best_positions"]["track_01_ridgeline_circuit"]), 1)

	var p2: Dictionary = migrated["player_profiles"]["P2"]
	assert_false((p2["best_laps"] as Dictionary).has(RESET_TRACK_ID))
	assert_false((p2["best_positions"] as Dictionary).has(RESET_TRACK_ID))
	assert_eq(int(p2["best_laps"]["track_04_ochre_rift"]), 95_000)

	assert_true((migrated["player_profiles"]["P3"]["best_laps"] as Dictionary).is_empty())
	assert_true((migrated["player_profiles"]["P4"]["best_laps"] as Dictionary).is_empty())


func test_v2_to_v3_migration_also_deletes_the_track_02_ghost_file() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	_write_ghost_fixture(RESET_TRACK_ID)
	_write_ghost_fixture("track_01_ridgeline_circuit")
	var v2_save: Dictionary = {
		"version": 2,
		"best_laps": {RESET_TRACK_ID: 65_000},
		"best_positions": {},
		"grand_prix_bests": {},
		"last_selection": {"driver": "", "kart": "medium", "track": "test_loop"},
		"unlocks": [],
		"player_profiles": {
			"P1": {"best_laps": {}, "best_positions": {}},
			"P2": {"best_laps": {}, "best_positions": {}},
			"P3": {"best_laps": {}, "best_positions": {}},
			"P4": {"best_laps": {}, "best_positions": {}},
		},
	}
	_write_text(SAVE_PATH, JSON.stringify(v2_save))

	manager.load_data()

	assert_false(FileAccess.file_exists(GHOST_DIRECTORY.path_join("%s.json" % RESET_TRACK_ID)))
	assert_true(FileAccess.file_exists(GHOST_DIRECTORY.path_join("track_01_ridgeline_circuit.json")))


func test_v3_save_is_left_alone_and_a_new_track_02_record_survives_reload() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	var v3_save: Dictionary = manager.default_data()
	assert_eq(int(v3_save["version"]), 3)
	_write_text(SAVE_PATH, JSON.stringify(v3_save))

	var loaded: Dictionary = manager.load_data()
	assert_eq(int(loaded["version"]), 3)
	assert_false((loaded["best_laps"] as Dictionary).has(RESET_TRACK_ID))

	assert_eq(manager.record_race_result(StringName(RESET_TRACK_ID), 55_000, 1), OK)
	var reloaded: Dictionary = manager.load_data()
	assert_eq(int(reloaded["best_laps"][RESET_TRACK_ID]), 55_000)
	assert_eq(int(reloaded["version"]), 3)


func test_corrupt_primary_recovers_a_v2_backup_and_still_migrates_it_to_v3() -> void:
	_write_text(SAVE_PATH, "{ definitely not json")
	var backup_data: Dictionary = {
		"version": 2,
		"best_laps": {"track_01_ridgeline_circuit": 71_000, RESET_TRACK_ID: 65_000},
		"best_positions": {},
		"last_selection": {"driver": "", "kart": "medium", "track": "test_loop"},
		"unlocks": [],
		"player_profiles": {
			"P1": {"best_laps": {RESET_TRACK_ID: 65_000}, "best_positions": {}},
			"P2": {"best_laps": {}, "best_positions": {}},
			"P3": {"best_laps": {}, "best_positions": {}},
			"P4": {"best_laps": {}, "best_positions": {}},
		},
	}
	_write_text(BACKUP_PATH, JSON.stringify(backup_data))
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)

	var recovered: Dictionary = manager.load_data()
	var restored: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))

	assert_eq(int(recovered["version"]), 3)
	assert_eq(int(recovered["best_laps"]["track_01_ridgeline_circuit"]), 71_000)
	assert_false((recovered["best_laps"] as Dictionary).has(RESET_TRACK_ID))
	assert_true(restored is Dictionary)
	assert_eq(int((restored as Dictionary)["version"]), 3)


func _write_ghost_fixture(track_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIRECTORY)
	var file: FileAccess = FileAccess.open(GHOST_DIRECTORY.path_join("%s.json" % track_id), FileAccess.WRITE)
	assert_not_null(file)
	file.store_string("fixture")
	file.close()


func _remove_ghost_fixtures() -> void:
	if not DirAccess.dir_exists_absolute(GHOST_DIRECTORY):
		return
	var dir: DirAccess = DirAccess.open(GHOST_DIRECTORY)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(GHOST_DIRECTORY.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


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

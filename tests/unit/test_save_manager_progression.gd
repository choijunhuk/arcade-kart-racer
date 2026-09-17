extends GutTest

## Phase 18e-3: SaveManager progression counters and the announced-unlock
## cache. Old saves without `stats` keep every record and gain the section.

const SAVE_PATH: String = "user://phase18e_progression_save_test.json"
const BACKUP_PATH: String = SAVE_PATH + ".bak"
const GHOST_DIRECTORY: String = "user://phase18e-progression-ghosts"


func before_each() -> void:
	_remove_test_files()


func after_each() -> void:
	_remove_test_files()


func test_default_save_carries_zeroed_stats() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	var data: Dictionary = manager.load_data()
	assert_eq(data["stats"], {"wins": 0, "races": 0})


func test_primary_profile_results_count_races_and_wins() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	assert_eq(manager.record_race_result(&"test_loop", 12_000, 1), OK)
	assert_eq(manager.record_race_result(&"test_loop", 13_000, 3), OK)
	assert_eq(manager.record_player_race_result(0, &"test_hairpin", 9_000, 1), OK)
	var data: Dictionary = manager.load_data()
	assert_eq(int(data["stats"]["races"]), 3)
	assert_eq(int(data["stats"]["wins"]), 2)


func test_other_local_players_do_not_touch_the_primary_stats() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	assert_eq(manager.record_player_race_result(1, &"test_loop", 12_000, 1), OK)
	assert_eq(manager.record_player_race_result(3, &"test_loop", 12_000, 1), OK)
	var data: Dictionary = manager.load_data()
	assert_eq(int(data["stats"]["races"]), 0)
	assert_eq(int(data["stats"]["wins"]), 0)
	assert_eq(int(data["player_profiles"]["P2"]["best_positions"]["test_loop"]), 1, "P2 record still saved")


func test_position_zero_keeps_the_lap_but_neither_a_position_nor_a_race() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	assert_eq(manager.record_race_result(&"test_loop", 12_000, 3), OK)
	assert_eq(manager.record_race_result(&"test_loop", 11_000, 0), OK, "a time trial / solo lap")
	assert_eq(manager.record_race_result(&"test_hairpin", 9_000, 0), OK)
	var data: Dictionary = manager.load_data()
	assert_eq(int(data["best_laps"]["test_loop"]), 11_000)
	assert_eq(int(data["best_laps"]["test_hairpin"]), 9_000)
	assert_eq(int(data["best_positions"]["test_loop"]), 3, "the real 3rd place survives")
	assert_false(data["best_positions"].has("test_hairpin"))
	assert_eq(int(data["stats"]["wins"]), 0)
	assert_eq(int(data["stats"]["races"]), 1, "solo laps are not races")


func test_v3_save_without_stats_keeps_records_and_gains_the_section() -> void:
	var v3_save: Dictionary = {
		"version": 3,
		"best_laps": {"track_01_ridgeline_circuit": 71_000, "track_03_glacier_crown": 80_000},
		"best_positions": {"track_01_ridgeline_circuit": 1, "track_03_glacier_crown": 3},
		"grand_prix_bests": {"horizon_cup/normal": {"position": 2, "points": 48}},
		"last_selection": {"driver": "aurora_vale", "kart": "heavy", "track": "track_03_glacier_crown"},
		"unlocks": ["kart:basalt_crown"],
		"player_profiles": {
			"P1": {"best_laps": {"track_01_ridgeline_circuit": 71_000}, "best_positions": {"track_01_ridgeline_circuit": 1}},
			"P2": {"best_laps": {"track_04_ochre_rift": 95_000}, "best_positions": {"track_04_ochre_rift": 2}},
			"P3": {"best_laps": {}, "best_positions": {}},
			"P4": {"best_laps": {}, "best_positions": {}},
		},
	}
	_write_text(SAVE_PATH, JSON.stringify(v3_save))
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)

	var loaded: Dictionary = manager.load_data()

	assert_eq(int(loaded["version"]), SaveManagerService.CURRENT_VERSION, "no version bump needed")
	assert_eq(loaded["stats"], {"wins": 0, "races": 0}, "missing stats are filled from defaults")
	assert_eq(int(loaded["best_laps"]["track_03_glacier_crown"]), 80_000)
	assert_eq(int(loaded["best_positions"]["track_03_glacier_crown"]), 3)
	assert_eq(int(loaded["grand_prix_bests"]["horizon_cup/normal"]["position"]), 2)
	assert_eq(loaded["last_selection"], v3_save["last_selection"])
	assert_eq(loaded["unlocks"], v3_save["unlocks"])
	assert_eq(int(loaded["player_profiles"]["P1"]["best_laps"]["track_01_ridgeline_circuit"]), 71_000)
	assert_eq(int(loaded["player_profiles"]["P2"]["best_positions"]["track_04_ochre_rift"]), 2)
	assert_eq(FileAccess.get_file_as_string(SAVE_PATH), JSON.stringify(v3_save), "an unchanged-version load never rewrites the file")

	assert_eq(manager.record_race_result(&"track_01_ridgeline_circuit", 70_000, 1), OK)
	var after: Dictionary = manager.load_data()
	assert_eq(int(after["stats"]["wins"]), 1)
	assert_eq(int(after["best_laps"]["track_03_glacier_crown"]), 80_000, "other records survive the first write")
	assert_eq(int(after["player_profiles"]["P2"]["best_laps"]["track_04_ochre_rift"]), 95_000)
	assert_eq(int(after["grand_prix_bests"]["horizon_cup/normal"]["points"]), 48)


func test_add_unlock_stores_each_key_once() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	assert_false(manager.is_unlock_stored("kart:zephyr_needle"))
	assert_eq(manager.add_unlock("kart:zephyr_needle"), OK)
	assert_eq(manager.add_unlock("kart:zephyr_needle"), OK)
	assert_eq(manager.add_unlock("track:track_03_glacier_crown"), OK)
	assert_true(manager.is_unlock_stored("kart:zephyr_needle"))
	assert_eq(manager.load_data()["unlocks"], ["kart:zephyr_needle", "track:track_03_glacier_crown"])


func test_add_unlocks_stores_every_missing_key_in_one_write() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	assert_eq(manager.add_unlock("kart:zephyr_needle"), OK)
	var keys: Array[String] = ["kart:zephyr_needle", "driver:nyx_calder", "mode:mirror", "driver:nyx_calder"]
	assert_eq(manager.add_unlocks(keys), OK)
	assert_eq(manager.load_data()["unlocks"], ["kart:zephyr_needle", "driver:nyx_calder", "mode:mirror"])
	var before: String = FileAccess.get_file_as_string(SAVE_PATH)
	var stored: Array[String] = ["mode:mirror", "kart:zephyr_needle"]
	assert_eq(manager.add_unlocks(stored), OK)
	assert_eq(FileAccess.get_file_as_string(SAVE_PATH), before, "nothing missing means no write")
	assert_eq(manager.add_unlocks([]), OK)


func test_a_non_dictionary_stats_section_is_treated_as_corrupt() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	var primary: Dictionary = manager.default_data()
	primary["stats"] = "lots"
	primary["best_laps"] = {"test_loop": 1_000}
	var backup: Dictionary = primary.duplicate(true)
	backup["stats"] = {"wins": 7, "races": 9}
	backup["best_laps"] = {"test_loop": 2_000}
	_write_text(SAVE_PATH, JSON.stringify(primary))
	_write_text(BACKUP_PATH, JSON.stringify(backup))

	var recovered: Dictionary = manager.load_data()

	assert_eq(int(recovered["best_laps"]["test_loop"]), 2_000, "the valid backup wins")
	assert_eq(int(recovered["stats"]["wins"]), 7)


func test_non_numeric_or_negative_stats_values_are_treated_as_corrupt() -> void:
	var manager: SaveManagerService = SaveManagerService.new(SAVE_PATH, GHOST_DIRECTORY)
	autofree(manager)
	for bad: Variant in [-1, "5", null, [3], -0.5, 5.5]:
		_remove_test_files()
		var primary: Dictionary = manager.default_data()
		primary["stats"] = {"wins": bad, "races": 2}
		primary["best_laps"] = {"test_loop": 1_000}
		var backup: Dictionary = manager.default_data()
		backup["stats"] = {"wins": 0, "races": 2.0}
		backup["best_laps"] = {"test_loop": 2_000}
		_write_text(SAVE_PATH, JSON.stringify(primary))
		_write_text(BACKUP_PATH, JSON.stringify(backup))
		var recovered: Dictionary = manager.load_data()
		assert_eq(int(recovered["best_laps"]["test_loop"]), 2_000, "the valid backup wins over wins=%s" % str(bad))
		assert_eq(int(recovered["stats"]["races"]), 2, "0 and whole floats stay legal")


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_test_files() -> void:
	for path: String in [SAVE_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

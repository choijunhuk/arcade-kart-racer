extends GutTest

const SPLIT_SCREEN_PATH: String = "res://race/split_screen.gd"
const PLAYER_SLOT_PATH: String = "res://data/schemas/player_slot.gd"
const LOBBY_STATE_PATH: String = "res://ui/menus/local_lobby_state.gd"
const SAVE_PATH: String = "user://phase14_profiles_test.json"


func before_each() -> void:
	_remove_save()


func after_each() -> void:
	_remove_save()


func test_one_player_layout_fills_the_output() -> void:
	var rects: Array = _layout_rects(1)
	if rects.is_empty():
		return
	assert_eq(rects, [Rect2(0.0, 0.0, 1.0, 1.0)])


func test_two_player_layout_uses_horizontal_halves() -> void:
	var rects: Array = _layout_rects(2)
	if rects.is_empty():
		return
	assert_eq(rects, [Rect2(0.0, 0.0, 1.0, 0.5), Rect2(0.0, 0.5, 1.0, 0.5)])


func test_three_player_layout_uses_three_quadrants() -> void:
	var rects: Array = _layout_rects(3)
	if rects.is_empty():
		return
	assert_eq(rects, [
		Rect2(0.0, 0.0, 0.5, 0.5),
		Rect2(0.5, 0.0, 0.5, 0.5),
		Rect2(0.0, 0.5, 0.5, 0.5),
	])


func test_four_player_layout_uses_all_quadrants() -> void:
	var rects: Array = _layout_rects(4)
	if rects.is_empty():
		return
	assert_eq(rects, [
		Rect2(0.0, 0.0, 0.5, 0.5),
		Rect2(0.5, 0.0, 0.5, 0.5),
		Rect2(0.0, 0.5, 0.5, 0.5),
		Rect2(0.5, 0.5, 0.5, 0.5),
	])


func test_race_config_counts_humans_and_ai_from_player_slots() -> void:
	var first: PlayerSlot = _player_slot(-1, 0)
	var second: PlayerSlot = _player_slot(1, 3)
	if first == null or second == null:
		return
	var config: RaceConfig = RaceConfig.new()
	config.kart_count = 8
	config.players = [first, second]
	assert_eq(int(config.call("human_count")), 2)
	assert_eq(int(config.call("ai_count")), 6)
	assert_true(bool(config.call("is_human_grid_slot", 0)))
	assert_true(bool(config.call("is_human_grid_slot", 3)))
	assert_false(bool(config.call("is_human_grid_slot", 2)))


func test_lobby_maps_keyboard_to_player_one_and_pads_by_join_order() -> void:
	var lobby: RefCounted = _lobby_state()
	if lobby == null:
		return
	assert_true(bool(lobby.call("join", -1)))
	assert_true(bool(lobby.call("join", 2)))
	assert_eq(int(lobby.call("player_index_for_device", -1)), 0)
	assert_eq(int(lobby.call("player_index_for_device", 2)), 1)


func test_lobby_rejects_duplicate_device_and_fifth_player() -> void:
	var lobby: RefCounted = _lobby_state()
	if lobby == null:
		return
	assert_true(bool(lobby.call("join", -1)))
	assert_false(bool(lobby.call("join", -1)))
	for device_id: int in [0, 1, 2]:
		assert_true(bool(lobby.call("join", device_id)))
	assert_false(bool(lobby.call("join", 3)))


func test_lobby_leave_compacts_player_and_grid_indices() -> void:
	var lobby: RefCounted = _lobby_state()
	if lobby == null:
		return
	for device_id: int in [-1, 0, 1]:
		lobby.call("join", device_id)
	assert_true(bool(lobby.call("leave", 0)))
	var slots: Array = lobby.call("players") as Array
	assert_eq(slots.size(), 2)
	assert_eq(int((slots[1] as Object).get("device_id")), 1)
	assert_eq(int((slots[1] as Object).get("grid_slot")), 1)


func test_lobby_starts_only_with_two_or_more_ready_players() -> void:
	var lobby: RefCounted = _lobby_state()
	if lobby == null:
		return
	lobby.call("join", -1)
	lobby.call("set_ready", -1, true)
	assert_false(bool(lobby.call("can_start")))
	lobby.call("join", 0)
	assert_false(bool(lobby.call("can_start")))
	lobby.call("set_ready", 0, true)
	assert_true(bool(lobby.call("can_start")))


func test_finishing_timeout_waits_for_all_humans_then_closes_at_margin() -> void:
	var manager_script: GDScript = load("res://race/race_manager.gd") as GDScript
	assert_false(bool(manager_script.call("finishing_complete", 3, 8, 14.9, 15.0, 1, 2)))
	assert_false(bool(manager_script.call("finishing_complete", 3, 8, 30.0, 15.0, 1, 2)))
	assert_false(bool(manager_script.call("finishing_complete", 3, 8, 14.9, 15.0, 2, 2)))
	assert_true(bool(manager_script.call("finishing_complete", 3, 8, 15.0, 15.0, 2, 2)))
	assert_true(bool(manager_script.call("finishing_complete", 8, 8, 0.0, 15.0, 2, 2)))


func test_results_order_keeps_rank_and_human_identity() -> void:
	var human: RaceResults.Entry = RaceResults.Entry.new()
	human.rank = 2
	var ai: RaceResults.Entry = RaceResults.Entry.new()
	ai.rank = 1
	var has_human_flag: bool = _has_property(human, &"is_human")
	assert_true(has_human_flag)
	if not has_human_flag:
		return
	human.set("is_human", true)
	human.set("player_number", 2)
	var ordered: Array[RaceResults.Entry] = ResultsOrdering.by_rank([human, ai])
	assert_eq(ordered[0], ai)
	assert_true(bool(ordered[1].get("is_human")))
	assert_eq(int(ordered[1].get("player_number")), 2)


func test_save_manager_keeps_separate_best_laps_for_p1_and_p2() -> void:
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(save)
	assert_true(save.has_method("record_player_race_result"))
	if not save.has_method("record_player_race_result"):
		return
	assert_eq(save.call("record_player_race_result", 0, &"test_loop", 10_000, 2), OK)
	assert_eq(save.call("record_player_race_result", 1, &"test_loop", 12_000, 1), OK)
	assert_eq(int(save.call("get_player_best_lap_ms", 0, &"test_loop")), 10_000)
	assert_eq(int(save.call("get_player_best_lap_ms", 1, &"test_loop")), 12_000)


func test_perf_probe_accepts_named_player_and_kart_counts() -> void:
	var script: GDScript = load("res://scenes/test/perf_probe.gd") as GDScript
	assert_true(script.has_method("parse_options"))
	if not script.has_method("parse_options"):
		return
	var options: Dictionary = script.call(
		"parse_options", PackedStringArray(["--players", "4", "--karts", "8", "--duration", "5"]),
	) as Dictionary
	assert_eq(int(options["players"]), 4)
	assert_eq(int(options["karts"]), 8)
	assert_almost_eq(float(options["duration"]), 5.0, 0.001)


func test_split_screen_render_scale_decreases_for_more_viewports() -> void:
	assert_almost_eq(SplitScreen.render_scale_for_players(1, 1.0), 1.0, 0.001)
	assert_almost_eq(SplitScreen.render_scale_for_players(2, 1.0), 0.85, 0.001)
	assert_almost_eq(SplitScreen.render_scale_for_players(4, 1.0), 0.70, 0.001)


func _layout_rects(player_count: int) -> Array:
	var exists: bool = ResourceLoader.exists(SPLIT_SCREEN_PATH)
	assert_true(exists, "SplitScreen script must exist")
	if not exists:
		return []
	return (load(SPLIT_SCREEN_PATH) as GDScript).call("layout_rects", player_count) as Array


func _player_slot(device_id: int, grid_slot: int) -> PlayerSlot:
	var exists: bool = ResourceLoader.exists(PLAYER_SLOT_PATH)
	assert_true(exists, "PlayerSlot resource must exist")
	if not exists:
		return null
	var slot: PlayerSlot = (load(PLAYER_SLOT_PATH) as GDScript).new() as PlayerSlot
	slot.set("device_id", device_id)
	slot.set("driver_id", &"aurora_vale")
	slot.set("kart_id", &"medium")
	slot.set("grid_slot", grid_slot)
	return slot


func _lobby_state() -> RefCounted:
	var exists: bool = ResourceLoader.exists(LOBBY_STATE_PATH)
	assert_true(exists, "LocalLobbyState script must exist")
	return (load(LOBBY_STATE_PATH) as GDScript).new() as RefCounted if exists else null


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false


func _remove_save() -> void:
	for path: String in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_legacy_records_migrate_to_p1_and_survive_first_result() -> void:
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(save)
	for version: int in [0, 1]:
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify({
			"version": version, "best_laps": {"test_loop": 9000, "track_02": 12000},
			"best_positions": {"test_loop": 2, "track_02": 1},
		}))
		file.close()
		var loaded: Dictionary = save.load_data()
		assert_eq(int(loaded["version"]), SaveManagerService.CURRENT_VERSION)
		assert_eq(loaded["player_profiles"]["P1"]["best_laps"], loaded["best_laps"])
		assert_eq(loaded["player_profiles"]["P1"]["best_positions"], loaded["best_positions"])
		assert_eq(save.record_player_race_result(0, &"test_loop", 8000, 1), OK)
		assert_eq(save.get_best_lap_ms(&"track_02"), 12000)
		assert_eq(save.get_player_best_lap_ms(0, &"track_02"), 12000)
		assert_eq(save.get_player_best_lap_ms(0, &"test_loop"), 8000)
		assert_eq(int(save.load_data()["best_positions"].get("track_02", -1)), 1)


func test_slower_lap_after_legacy_migration_is_not_a_new_record() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "best_laps": {"test_loop": 9000}}))
	file.close()
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var results: RaceResults = RaceResults.new()
	add_child_autofree(results)
	var player: KartController = KartController.new()
	autofree(player)
	results.setup(&"test_loop", [player], player, save)
	EventBus.lap_completed.emit(player, 1, 10.0)
	var entries: Array[RaceResults.Entry] = results.finalize([player], {player.get_instance_id(): 10.0})
	assert_false(entries[0].is_new_record)
	assert_eq(save.get_player_best_lap_ms(0, &"test_loop"), 9000)


func test_single_player_configs_accept_simulated_joypad_throttle() -> void:
	var built: RaceConfig = RaceConfigBuilder.build(
		preload("res://data/drivers/aurora_vale.tres"), preload("res://data/karts/medium.tres"),
		preload("res://data/tracks/track_01.tres"), preload("res://data/ai/normal.tres"),
	)
	var legacy: RaceConfig = RaceConfig.new()
	RaceConfigBuilder.normalize(legacy)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for config: RaceConfig in [built, legacy]:
		assert_ne(config.players[0].device_id, PlayerInputProvider.DEVICE_KEYBOARD)
		var provider: PlayerInputProvider = PlayerInputProvider.new(config.players[0].device_id)
		assert_gt(provider.get_frame().throttle, 0.5)
	var keyboard: PlayerInputProvider = PlayerInputProvider.new(PlayerInputProvider.DEVICE_KEYBOARD)
	assert_eq(keyboard.get_frame().throttle, 0.0)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_finishing_timer_does_not_accumulate_while_second_human_races() -> void:
	var manager: RaceManager = RaceManager.new()
	autofree(manager)
	var tracker: LapTracker = LapTracker.new()
	autofree(tracker)
	var first: KartController = KartController.new()
	var second: KartController = KartController.new()
	var ai: KartController = KartController.new()
	for kart: KartController in [first, second, ai]:
		autofree(kart)
		tracker.register_kart(kart)
	manager._lap_tracker = tracker
	manager._karts = [first, second, ai]
	manager._player_karts = [first, second]
	manager.tuning = manager.tuning.duplicate() as RaceTuning
	manager.tuning.finish_timeout_seconds = 15.0
	manager.tuning.results_delay_seconds = 10.0
	tracker._records[first.get_instance_id()].finished = true
	manager._advance_finishing(30.0)
	assert_eq(manager._finishing_elapsed, 0.0)
	assert_lt(manager._results_delay_remaining, 0.0)
	tracker._records[second.get_instance_id()].finished = true
	manager._advance_finishing(14.0)
	assert_lt(manager._results_delay_remaining, 0.0)
	manager._advance_finishing(1.0)
	assert_gt(manager._results_delay_remaining, 0.0)


func test_migration_merges_existing_profile_using_best_records() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": 1, "best_laps": {"test_loop": 9000}, "best_positions": {"test_loop": 1},
		"player_profiles": {
			"P1": {"best_laps": {"test_loop": 8000, "track_02": 12000}, "best_positions": {"test_loop": 2}},
			"P2": {"best_laps": {"test_loop": 7000}, "best_positions": {}},
		},
	}))
	file.close()
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(save)
	var data: Dictionary = save.load_data()
	assert_eq(int(data["best_laps"]["test_loop"]), 8000)
	assert_eq(int(data["best_laps"]["track_02"]), 12000)
	assert_eq(int(data["player_profiles"]["P1"]["best_positions"]["test_loop"]), 1)
	assert_eq(save.get_player_best_lap_ms(1, &"test_loop"), 7000)


func test_p1_mirror_merge_preserves_top_level_only_tracks() -> void:
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	autofree(save)
	var data: Dictionary = save.default_data()
	data["best_laps"] = {"track_02": 12000}
	data["best_positions"] = {"track_02": 2}
	assert_eq(save.save_data(data), OK)
	assert_eq(save.record_player_race_result(0, &"test_loop", 9000, 1), OK)
	assert_eq(save.get_best_lap_ms(&"track_02"), 12000)
	assert_eq(int(save.load_data()["best_positions"].get("track_02", -1)), 2)

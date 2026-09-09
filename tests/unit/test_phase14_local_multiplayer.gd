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


func test_finishing_timeout_starts_with_first_human_and_closes_at_margin() -> void:
	var manager_script: GDScript = load("res://race/race_manager.gd") as GDScript
	assert_false(bool(manager_script.call("finishing_complete", 3, 8, 14.9, 15.0, 1, 2)))
	assert_true(bool(manager_script.call("finishing_complete", 3, 8, 15.0, 15.0, 1, 2)))
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

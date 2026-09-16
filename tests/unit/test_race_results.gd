extends GutTest

const RESULTS_PATH: String = "res://race/race_results.gd"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const SAVE_PATH: String = "user://phase5_race_results_test.json"


func before_each() -> void:
	_remove_save()


func after_each() -> void:
	_remove_save()


func test_results_aggregate_rank_time_best_lap_hits_and_item_uses() -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var first: KartController = _make_kart("First")
	var second: KartController = _make_kart("Second")
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var karts: Array[KartController] = [first, second]
	results.call("setup", &"test_loop", karts, first, save)
	EventBus.lap_completed.emit(first, 1, 10.0)
	EventBus.lap_completed.emit(first, 2, 19.0)
	EventBus.kart_hit.emit(first, HitReactor.HitType.BUMP)
	EventBus.item_used.emit(first, &"nitro_can")
	EventBus.item_used.emit(first, &"nitro_can")
	var finish_times: Dictionary = {first.get_instance_id(): 19.0, second.get_instance_id(): 22.5}
	var ranking: Array[KartController] = [first, second]
	var entries: Array = results.call("finalize", ranking, finish_times) as Array

	assert_eq(entries.size(), 2)
	var entry: RefCounted = entries[0] as RefCounted
	assert_eq(int(entry.get("rank")), 1)
	assert_almost_eq(float(entry.get("total_time_seconds")), 19.0, 0.001)
	assert_almost_eq(float(entry.get("best_lap_seconds")), 9.0, 0.001)
	assert_eq(int(entry.get("hit_count")), 1)
	assert_eq(int(entry.get("item_use_count")), 2)


func test_player_result_writes_track_best_lap_and_position() -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var player: KartController = _make_kart("Player")
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var karts: Array[KartController] = [player]
	results.call("setup", &"test_loop", karts, player, save)
	EventBus.lap_completed.emit(player, 1, 8.75)
	results.call("finalize", karts, {player.get_instance_id(): 8.75})
	var data: Dictionary = save.load_data()
	assert_eq(int(data["best_laps"]["test_loop"]), 8750)
	assert_eq(int(data["best_positions"]["test_loop"]), 1)


func test_results_include_driver_kart_display_and_new_record_status() -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var player: KartController = _make_kart("Player")
	var driver: DriverData = preload("res://data/drivers/aurora_vale.tres")
	player.set_driver_data(driver)
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var karts: Array[KartController] = [player]
	results.call("setup", &"test_loop", karts, player, save)
	EventBus.lap_completed.emit(player, 1, 8.5)
	var entries: Array = results.call("finalize", karts, {player.get_instance_id(): 8.5}) as Array
	var entry: RaceResults.Entry = entries[0] as RaceResults.Entry
	var has_fields: bool = _has_property(entry, &"driver_name") and _has_property(entry, &"kart_display_name") and _has_property(entry, &"is_new_record")
	assert_true(has_fields)
	if not has_fields:
		return
	assert_eq(str(entry.get("driver_name")), driver.display_name)
	assert_eq(str(entry.get("kart_display_name")), player.get_kart_data().display_name)
	assert_true(bool(entry.get("is_new_record")))


func test_finalize_announces_newly_earned_unlocks_once() -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var player: KartController = _make_kart("Player")
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var karts: Array[KartController] = [player]
	results.call("setup", &"track_02_lumen_underpass", karts, player, save)
	EventBus.lap_completed.emit(player, 1, 8.75)
	results.call("finalize", karts, {player.get_instance_id(): 8.75})

	assert_eq(results.get("newly_unlocked"), ["track:track_03_glacier_crown"], "top 3 on track_02 opens track_03")
	assert_true(save.is_unlock_stored("track:track_03_glacier_crown"))
	assert_eq(int(save.load_data()["stats"]["wins"]), 1)

	results.call("setup", &"track_02_lumen_underpass", karts, player, save)
	results.call("finalize", karts, {player.get_instance_id(): 9.0})
	assert_eq(results.get("newly_unlocked"), [], "an already announced unlock is not repeated")


func test_ai_only_finalize_evaluates_no_unlocks() -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var bot: KartController = _make_kart("Bot")
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var karts: Array[KartController] = [bot]
	results.call("setup", &"track_02_lumen_underpass", karts, null, save)
	results.call("finalize", karts, {bot.get_instance_id(): 8.0})
	assert_eq(results.get("newly_unlocked"), [])
	assert_false(save.is_unlock_stored("track:track_03_glacier_crown"))


func test_time_trial_finalize_records_only_the_best_lap() -> void:
	_assert_non_competitive_race(_config(RaceConfig.RaceMode.TIME_TRIAL, 1))


func test_single_kart_race_finalize_records_only_the_best_lap() -> void:
	_assert_non_competitive_race(_config(RaceConfig.RaceMode.SINGLE_RACE, 1))


func test_eight_kart_win_counts_position_stats_and_unlocks() -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var player: KartController = _make_kart("Player")
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	var karts: Array[KartController] = [player]
	var finish_times: Dictionary = {player.get_instance_id(): 8.75}
	for index: int in range(7):
		var bot: KartController = _make_kart("Bot%d" % index)
		karts.append(bot)
		finish_times[bot.get_instance_id()] = 9.0 + index
	var players: Array[KartController] = [player]
	results.call("setup_players", &"track_02_lumen_underpass", karts, players, save, _config(RaceConfig.RaceMode.SINGLE_RACE, 8))
	EventBus.lap_completed.emit(player, 1, 8.75)
	results.call("finalize", karts, finish_times)
	var data: Dictionary = save.load_data()
	assert_eq(int(data["best_positions"]["track_02_lumen_underpass"]), 1)
	assert_eq(int(data["stats"]["wins"]), 1)
	assert_eq(int(data["stats"]["races"]), 1)
	assert_eq(results.get("newly_unlocked"), ["track:track_03_glacier_crown"])
	assert_true(save.is_unlock_stored("track:track_03_glacier_crown"))


## Time trials and solo races finish "1st" by construction: the lap is kept for
## the best_laps_all rule, but no position, race/win count, or unlock may follow.
func _assert_non_competitive_race(config: RaceConfig) -> void:
	var results: Node = _make_results()
	if results == null:
		return
	var player: KartController = _make_kart("Player")
	var save: SaveManagerService = SaveManagerService.new(SAVE_PATH)
	add_child_autofree(save)
	assert_eq(save.record_race_result(&"track_02_lumen_underpass", 9_000, 4), OK, "an earlier 4th place is on record")
	var karts: Array[KartController] = [player]
	var players: Array[KartController] = [player]
	results.call("setup_players", &"track_02_lumen_underpass", karts, players, save, config)
	EventBus.lap_completed.emit(player, 1, 8.75)
	results.call("finalize", karts, {player.get_instance_id(): 8.75})
	var data: Dictionary = save.load_data()
	assert_eq(int(data["best_laps"]["track_02_lumen_underpass"]), 8750, "the best lap is still written")
	assert_eq(int(data["best_positions"]["track_02_lumen_underpass"]), 4, "the solo rank 1 never replaces a real position")
	assert_eq(int(data["stats"]["wins"]), 0)
	assert_eq(int(data["stats"]["races"]), 1, "only the earlier competitive race counts")
	assert_eq(results.get("newly_unlocked"), [])
	assert_false(save.is_unlock_stored("track:track_03_glacier_crown"))


func _config(mode: RaceConfig.RaceMode, kart_count: int) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.race_mode = mode
	config.kart_count = kart_count
	return config


func _make_results() -> Node:
	var exists: bool = ResourceLoader.exists(RESULTS_PATH)
	assert_true(exists, "RaceResults script must exist")
	if not exists:
		return null
	var results: Node = (load(RESULTS_PATH) as GDScript).new() as Node
	add_child_autofree(results)
	return results


func _make_kart(node_name: String) -> KartController:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	kart.name = node_name
	add_child_autofree(kart)
	return kart


func _remove_save() -> void:
	for path: String in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false

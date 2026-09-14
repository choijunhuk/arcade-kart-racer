extends GutTest

## Headless smoke test (Phase 18d-3, plus 18d-3 review fix #1): a short
## simulated local race, driven purely through EventBus, writes one
## telemetry JSON per locally-recorded kart matching the documented schema
## to an injected directory, while a remote/AI kart's events are ignored
## entirely. Also covers split-screen isolation: two local human karts must
## never share a log bucket.

var _service: RaceTelemetryService
var _player_kart: KartController
var _second_player_kart: KartController
var _ai_kart: KartController
var _directory: String


func before_each() -> void:
	_directory = "user://test_telemetry_integration_%d" % Time.get_ticks_usec()
	_service = RaceTelemetryService.new()
	_service.enabled_override = true
	_service.telemetry_directory = _directory
	_service.track_id_override = &"test_loop"
	add_child_autofree(_service)

	_player_kart = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(_player_kart)
	_player_kart.input_provider = PlayerInputProvider.new()

	_second_player_kart = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(_second_player_kart)
	_second_player_kart.input_provider = PlayerInputProvider.new()

	_ai_kart = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(_ai_kart)
	_ai_kart.input_provider = InputProvider.new()


func after_each() -> void:
	var dir: DirAccess = DirAccess.open(_directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(_directory)


func test_short_race_writes_one_json_file_matching_the_documented_schema() -> void:
	EventBus.race_started.emit()

	# Lap 1: one drift release, one boost, one item, one hit (closed by the
	# boost path), one wall impact, one respawn.
	EventBus.drift_started.emit(_player_kart, 1)
	EventBus.drift_ended.emit(_player_kart, 2)
	EventBus.kart_hit.emit(_player_kart, HitReactor.HitType.BUMP)
	EventBus.boost_started.emit(_player_kart, BoostSpecData.new())
	EventBus.item_used.emit(_player_kart, &"nitro_can")
	EventBus.wall_impacted.emit(_player_kart)
	EventBus.kart_respawned.emit(_player_kart)
	# The AI kart's events must never reach the log.
	EventBus.drift_started.emit(_ai_kart, -1)
	EventBus.drift_ended.emit(_ai_kart, 3)
	EventBus.wall_impacted.emit(_ai_kart)
	EventBus.lap_completed.emit(_player_kart, 1, 32.5)

	# Lap 2: a whiffed drift release only.
	EventBus.drift_started.emit(_player_kart, -1)
	EventBus.drift_ended.emit(_player_kart, 0)
	EventBus.lap_completed.emit(_player_kart, 2, 30.1)

	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	var files: PackedStringArray = _list_json_files(_directory)
	assert_eq(files.size(), 1, "exactly one telemetry file must be written for one recorded local kart")
	if files.is_empty():
		return
	assert_true(files[0].ends_with("-test_loop-p1.json"), "the filename must end with -<track>-p<player_index+1>.json")

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(files[0])))
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed as Dictionary
	assert_eq(int(data["version"]), 1)
	assert_true(data.has("laps"))
	assert_true(data.has("totals"))
	assert_eq(int(data["player_index"]), 0, "the only recorded kart must be player_index 0")
	assert_eq(String(data.get("kart_id", "")), "medium", "kart_id must be included when cheaply available")

	var laps: Array = data["laps"]
	assert_eq(laps.size(), 2)
	var lap1: Dictionary = laps[0]
	assert_eq(int(lap1["lap"]), 1)
	assert_eq(int(lap1["drifts_started"]), 1)
	assert_eq(int((lap1["drift_release_tiers"] as Dictionary)["2"]), 1)
	assert_eq(int(lap1["items_used"]), 1)
	assert_eq(int(lap1["hits"]), 1)
	assert_eq(int(lap1["wall_impacts"]), 1, "the AI kart's wall impact must be excluded")
	assert_eq(int(lap1["respawns"]), 1)
	assert_almost_eq(float(lap1["lap_time"]), 32.5, 0.001)
	assert_false((lap1["hit_recovery_seconds"] as Array).is_empty(), "the hit must have a recorded recovery time")

	var lap2: Dictionary = laps[1]
	assert_eq(int((lap2["drift_release_tiers"] as Dictionary)["0"]), 1)
	assert_almost_eq(float(lap2["lap_time"]), 30.1, 0.001)

	var totals: Dictionary = data["totals"]
	assert_eq(int(totals["laps_completed"]), 2)
	assert_eq(int(totals["drifts_started"]), 2, "only the local human kart's drifts must be counted")


## 18d-3 review fix #1: two local human karts (split-screen) must never share
## a log bucket. Interleaved events land in separate per-player files with no
## cross-contamination.
func test_split_screen_two_local_karts_write_separate_files_with_no_cross_contamination() -> void:
	EventBus.race_started.emit()

	EventBus.drift_started.emit(_player_kart, 1)
	EventBus.drift_started.emit(_second_player_kart, -1)
	EventBus.drift_ended.emit(_player_kart, 2)
	EventBus.drift_ended.emit(_second_player_kart, 1)
	EventBus.kart_hit.emit(_second_player_kart, HitReactor.HitType.BUMP)
	EventBus.wall_impacted.emit(_player_kart)
	EventBus.boost_started.emit(_second_player_kart, BoostSpecData.new())
	EventBus.lap_completed.emit(_player_kart, 1, 20.0)
	EventBus.lap_completed.emit(_second_player_kart, 1, 25.0)

	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	var files: PackedStringArray = _list_json_files(_directory)
	assert_eq(files.size(), 2, "one file per recorded local kart must be written")
	if files.size() != 2:
		return

	var p1_file: String = ""
	var p2_file: String = ""
	for file_name: String in files:
		if file_name.ends_with("-p1.json"):
			p1_file = file_name
		elif file_name.ends_with("-p2.json"):
			p2_file = file_name
	assert_false(p1_file.is_empty(), "a -p1.json file must exist")
	assert_false(p2_file.is_empty(), "a -p2.json file must exist")
	if p1_file.is_empty() or p2_file.is_empty():
		return

	var p1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(p1_file)))
	var p2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(p2_file)))

	assert_eq(int(p1["player_index"]), 0)
	assert_eq(int(p2["player_index"]), 1)

	var p1_lap1: Dictionary = (p1["laps"] as Array)[0]
	var p1_tiers: Dictionary = p1_lap1["drift_release_tiers"]
	assert_eq(p1_tiers.keys(), ["2"], "player 1's drift tier must not include player 2's release")
	assert_eq(int(p1_tiers.get("2", 0)), 1)
	assert_eq(int(p1_lap1["hits"]), 0, "player 2's hit must not leak into player 1's log")
	assert_eq(int(p1_lap1["wall_impacts"]), 1)
	assert_almost_eq(float(p1_lap1["lap_time"]), 20.0, 0.001)

	var p2_lap1: Dictionary = (p2["laps"] as Array)[0]
	var p2_tiers: Dictionary = p2_lap1["drift_release_tiers"]
	assert_eq(p2_tiers.keys(), ["1"], "player 2's drift tier must not include player 1's release")
	assert_eq(int(p2_tiers.get("1", 0)), 1)
	assert_eq(int(p2_lap1["hits"]), 1)
	assert_eq(int(p2_lap1["wall_impacts"]), 0, "player 1's wall impact must not leak into player 2's log")
	assert_false((p2_lap1["hit_recovery_seconds"] as Array).is_empty(), "player 2's hit must have a recorded recovery time")
	assert_almost_eq(float(p2_lap1["lap_time"]), 25.0, 0.001)


## 18d-3 review fix #2: `_update_pending_recoveries()` must resolve every
## kart's pending recovery in a single pass (verifying `keys()` remains a
## safe erase-while-iterating snapshot after dropping the redundant
## `.duplicate()`), and must not error when nothing is pending.
func test_physics_process_resolves_every_pending_recovery_in_one_pass() -> void:
	_service.set_physics_process(false)
	EventBus.race_started.emit()

	# Nothing pending yet: must be a safe no-op.
	_service._physics_process(1.0 / 60.0)
	assert_true(_service._pending_recovery.is_empty())

	EventBus.kart_hit.emit(_player_kart, HitReactor.HitType.BUMP)
	EventBus.kart_hit.emit(_second_player_kart, HitReactor.HitType.BUMP)
	assert_eq(_service._pending_recovery.size(), 2)

	# Both karts are at rest (speed 0 == 0 * ratio), so the very next pass
	# must resolve both pending recoveries in the same call.
	_service._physics_process(1.0 / 60.0)
	assert_true(_service._pending_recovery.is_empty(), "every pending recovery must resolve in one _update_pending_recoveries() pass")


## 18d-3 review fix #3: a second hit landing before the first recovery
## resolves must not fabricate the first hit's recovery time at the second
## hit's timestamp. Both hits are counted and each closes with its own,
## real elapsed recovery time once resolution (here, a boost) happens.
func test_second_hit_before_recovery_does_not_fabricate_the_first_recovery() -> void:
	EventBus.race_started.emit()

	EventBus.kart_hit.emit(_player_kart, HitReactor.HitType.BUMP)
	_service._elapsed_seconds = 0.5
	EventBus.kart_hit.emit(_player_kart, HitReactor.HitType.BUMP)
	_service._elapsed_seconds = 1.2
	EventBus.boost_started.emit(_player_kart, BoostSpecData.new())

	EventBus.lap_completed.emit(_player_kart, 1, 5.0)
	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	var files: PackedStringArray = _list_json_files(_directory)
	assert_eq(files.size(), 1)
	if files.is_empty():
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(files[0])))
	var lap1: Dictionary = (data["laps"] as Array)[0]
	assert_eq(int(lap1["hits"]), 2)
	var recovery: Array = lap1["hit_recovery_seconds"]
	assert_eq(recovery.size(), 2, "both hits must produce a recovery entry")
	if recovery.size() != 2:
		return
	assert_almost_eq(float(recovery[0]), 1.2, 0.0001, "the first hit's recovery must use its own original hit time (0.0), not the second hit's time")
	assert_almost_eq(float(recovery[1]), 0.7, 0.0001, "the second hit's recovery must use its own hit time (0.5)")


## 18d-3 review fix #3 decision: a recovery still pending when the race ends
## is recorded as capped (not silently dropped), so hits and
## hit_recovery_seconds stay in sync.
func test_pending_recovery_at_race_end_is_capped_not_dropped() -> void:
	EventBus.race_started.emit()

	EventBus.kart_hit.emit(_player_kart, HitReactor.HitType.BUMP)
	_service._elapsed_seconds = 3.0

	EventBus.lap_completed.emit(_player_kart, 1, 5.0)
	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	var files: PackedStringArray = _list_json_files(_directory)
	assert_eq(files.size(), 1)
	if files.is_empty():
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(files[0])))
	var lap1: Dictionary = (data["laps"] as Array)[0]
	assert_eq(int(lap1["hits"]), 1)
	var recovery: Array = lap1["hit_recovery_seconds"]
	assert_eq(recovery.size(), 1, "a pending recovery at race end must still be recorded, not dropped")
	if recovery.size() != 1:
		return
	assert_almost_eq(float(recovery[0]), 3.0, 0.0001, "the capped recovery must use the elapsed time at race end")


## 18d-3 review fix #5: trigger a real boost through the kart's own
## BoostController request path (KartController.request_boost, the same
## entry point drift release/boost pads/start boost all use) and assert the
## real source key is recorded, not "unknown".
func test_boost_started_through_the_real_boost_controller_path_records_the_real_source() -> void:
	EventBus.race_started.emit()

	var spec: BoostSpecData = BoostSpecData.new()
	spec.speed_mult = 1.5
	spec.duration = 1.0
	_player_kart.request_boost(spec, &"boost_pad")

	EventBus.lap_completed.emit(_player_kart, 1, 10.0)
	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	var files: PackedStringArray = _list_json_files(_directory)
	assert_eq(files.size(), 1)
	if files.is_empty():
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(files[0])))
	var lap1: Dictionary = (data["laps"] as Array)[0]
	var sources: Dictionary = lap1["boosts_by_source"]
	assert_eq(sources.keys(), ["boost_pad"], "the real BoostController source must be recorded, not unknown")
	assert_eq(int(sources.get("boost_pad", 0)), 1)


## 18d-4 review fix #1: player_index must follow the race's stable
## roster (join order), not "whichever local kart fires the first tracked
## EventBus signal first" — the second roster kart firing first must still
## land in roster slot 0 (-p1.json), not steal it from the first roster kart.
func test_player_index_follows_roster_order_even_when_player_two_fires_first() -> void:
	_service.roster_override = [_player_kart, _second_player_kart]
	EventBus.race_started.emit()

	# _second_player_kart (roster slot 1) fires first, and with more
	# activity than _player_kart (roster slot 0), so the bug under test
	# (index-by-arrival-order) would put the busier kart in p1.json.
	EventBus.wall_impacted.emit(_second_player_kart)
	EventBus.wall_impacted.emit(_second_player_kart)
	EventBus.wall_impacted.emit(_player_kart)
	EventBus.lap_completed.emit(_second_player_kart, 1, 25.0)
	EventBus.lap_completed.emit(_player_kart, 1, 20.0)

	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	var files: PackedStringArray = _list_json_files(_directory)
	assert_eq(files.size(), 2)
	if files.size() != 2:
		return

	var p1_file: String = ""
	var p2_file: String = ""
	for file_name: String in files:
		if file_name.ends_with("-p1.json"):
			p1_file = file_name
		elif file_name.ends_with("-p2.json"):
			p2_file = file_name
	assert_false(p1_file.is_empty())
	assert_false(p2_file.is_empty())
	if p1_file.is_empty() or p2_file.is_empty():
		return

	var p1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(p1_file)))
	var p2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(p2_file)))
	assert_eq(int(p1["player_index"]), 0)
	assert_eq(int(p2["player_index"]), 1)

	var p1_lap1: Dictionary = (p1["laps"] as Array)[0]
	var p2_lap1: Dictionary = (p2["laps"] as Array)[0]
	assert_eq(int(p1_lap1["wall_impacts"]), 1, "roster slot 0 (-p1.json) must be _player_kart, not whichever kart fired first")
	assert_eq(int(p2_lap1["wall_impacts"]), 2, "roster slot 1 (-p2.json) must be _second_player_kart even though it fired first")


func _list_json_files(directory: String) -> PackedStringArray:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return PackedStringArray()
	var files: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return files

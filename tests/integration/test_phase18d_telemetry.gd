extends GutTest

## Headless smoke test (Phase 18d-3): a short simulated local race, driven
## purely through EventBus, writes one telemetry JSON matching the documented
## schema to an injected directory, while a remote/AI kart's events are
## ignored entirely.

var _service: RaceTelemetryService
var _player_kart: KartController
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
	assert_eq(files.size(), 1, "exactly one telemetry file must be written on RESULTS")
	if files.is_empty():
		return
	assert_true(files[0].ends_with("-test_loop.json"), "the filename must end with -<track>.json")

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(files[0])))
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed as Dictionary
	assert_eq(int(data["version"]), 1)
	assert_true(data.has("laps"))
	assert_true(data.has("totals"))

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

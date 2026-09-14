extends GutTest

## Pure gating/recovery/identity tests for RaceTelemetryService (Phase 18d-3),
## plus the write_and_rotate file helper and the disabled-setting/automation/
## tutorial/headless recording gate on a real (test-directed) instance.

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")

var _directory: String


func before_each() -> void:
	_directory = "user://test_telemetry_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_directory(_directory)
	GameState.net_session = null


func test_is_recording_enabled_requires_every_gate_to_pass() -> void:
	assert_true(RaceTelemetryService.is_recording_enabled(true, false, false, false))
	assert_false(RaceTelemetryService.is_recording_enabled(false, false, false, false), "setting off must block recording")
	assert_false(RaceTelemetryService.is_recording_enabled(true, true, false, false), "headless must block recording")
	assert_false(RaceTelemetryService.is_recording_enabled(true, false, true, false), "automation_mode must block recording")
	assert_false(RaceTelemetryService.is_recording_enabled(true, false, false, true), "tutorial_active must block recording")


func test_is_recovered_true_once_speed_regains_the_ratio() -> void:
	assert_false(RaceTelemetryService.is_recovered(7.9, 10.0, 0.1), "79% of pre-hit speed is still below the 80% threshold")
	assert_true(RaceTelemetryService.is_recovered(8.0, 10.0, 0.1), "exactly 80% of pre-hit speed counts as recovered")
	assert_true(RaceTelemetryService.is_recovered(-9.0, 10.0, 0.1), "recovery compares speed magnitude, not sign")


func test_is_recovered_true_at_the_cap_regardless_of_speed() -> void:
	assert_false(RaceTelemetryService.is_recovered(0.0, 10.0, 9.999))
	assert_true(RaceTelemetryService.is_recovered(0.0, 10.0, 10.0), "the 10s cap must force recovery even far below the ratio")
	assert_true(RaceTelemetryService.is_recovered(0.0, 10.0, 999.0))


func test_is_local_human_kart_true_only_for_player_input_provider() -> void:
	var player_kart: KartController = KartController.new()
	player_kart.input_provider = PlayerInputProvider.new()
	autofree(player_kart)
	assert_true(RaceTelemetryService.is_local_human_kart(player_kart))

	var ai_kart: KartController = KartController.new()
	ai_kart.input_provider = InputProvider.new()
	autofree(ai_kart)
	assert_false(RaceTelemetryService.is_local_human_kart(ai_kart), "a non-player InputProvider (AI/ghost/remote) must be excluded")

	var not_a_kart: Node = Node.new()
	autofree(not_a_kart)
	assert_false(RaceTelemetryService.is_local_human_kart(not_a_kart))


## Audit finding 3: online, a remote player's kart uses the exact same
## `PlayerInputProvider` this machine's own kart does, so `is_local_human_kart()`
## alone can't exclude it — only `_resolve_roster()`'s local-only roster
## (`roster_override` here, `RaceManager.get_local_human_karts()` in
## production) can. Without the fix this test's remote kart would get its
## own telemetry file written on the local machine for a race it wasn't
## controlled from here.
func test_track_excludes_a_remote_kart_when_networked_even_with_player_input_provider() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	GameState.net_session = session
	var local_kart: KartController = KART_SCENE.instantiate() as KartController
	local_kart.input_provider = PlayerInputProvider.new()
	add_child_autofree(local_kart)
	var remote_kart: KartController = KART_SCENE.instantiate() as KartController
	remote_kart.input_provider = PlayerInputProvider.new()
	add_child_autofree(remote_kart)
	var service: RaceTelemetryService = RaceTelemetryService.new()
	service.enabled_override = true
	service.roster_override = [local_kart]
	add_child_autofree(service)
	service._on_race_started()
	service._on_drift_started(local_kart, 1)
	service._on_drift_started(remote_kart, 1)
	var logs: Dictionary = service.get("_logs")
	assert_eq(logs.size(), 1, "only the local kart may ever open a log")
	assert_true(logs.has(local_kart.get_instance_id()))
	assert_false(logs.has(remote_kart.get_instance_id()), "a remote networked kart must never get its own telemetry log")

## Offline regression: with no net_session, every PlayerInputProvider kart is
## still local (18d-4's lazy fallback for when no RaceManager is reachable).
func test_track_still_includes_any_player_kart_when_offline() -> void:
	GameState.net_session = null
	var kart: KartController = KART_SCENE.instantiate() as KartController
	kart.input_provider = PlayerInputProvider.new()
	add_child_autofree(kart)
	var service: RaceTelemetryService = RaceTelemetryService.new()
	service.enabled_override = true
	add_child_autofree(service)
	service._on_race_started()
	service._on_drift_started(kart, 1)
	assert_true((service.get("_logs") as Dictionary).has(kart.get_instance_id()))

func test_write_and_rotate_creates_a_json_file_with_the_given_contents() -> void:
	var error: Error = RaceTelemetryService.write_and_rotate(_directory, "20260101-000000-test_loop.json", {"version": 1, "laps": []}, 20)

	assert_eq(error, OK)
	var path: String = _directory.path_join("20260101-000000-test_loop.json")
	assert_true(FileAccess.file_exists(path))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(data["version"]), 1)
	assert_eq(data["laps"], [])


func test_write_and_rotate_keeps_only_the_newest_20_files() -> void:
	for index: int in range(25):
		var error: Error = RaceTelemetryService.write_and_rotate(_directory, "%03d.json" % index, {"index": index}, 20)
		assert_eq(error, OK)

	var remaining: PackedStringArray = _list_json_files(_directory)
	assert_eq(remaining.size(), 20, "rotation must keep exactly 20 files")
	assert_eq(remaining[0], "005.json", "the 5 oldest files must have been removed")
	assert_eq(remaining[remaining.size() - 1], "024.json")


## 18d-3 review fix #4: two writes within the same 1s-resolution filename
## must not clobber each other; the second (and third, ...) get a -2, -3, ...
## suffix instead.
func test_write_and_rotate_appends_a_suffix_on_filename_collision() -> void:
	var first_error: Error = RaceTelemetryService.write_and_rotate(_directory, "20260101-000000-test_loop.json", {"index": 0}, 20)
	var second_error: Error = RaceTelemetryService.write_and_rotate(_directory, "20260101-000000-test_loop.json", {"index": 1}, 20)
	var third_error: Error = RaceTelemetryService.write_and_rotate(_directory, "20260101-000000-test_loop.json", {"index": 2}, 20)

	assert_eq(first_error, OK)
	assert_eq(second_error, OK)
	assert_eq(third_error, OK)

	var remaining: PackedStringArray = _list_json_files(_directory)
	assert_eq(remaining.size(), 3, "all three writes must land in distinct files")
	assert_true(FileAccess.file_exists(_directory.path_join("20260101-000000-test_loop.json")))
	assert_true(FileAccess.file_exists(_directory.path_join("20260101-000000-test_loop-2.json")))
	assert_true(FileAccess.file_exists(_directory.path_join("20260101-000000-test_loop-3.json")))

	var first_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("20260101-000000-test_loop.json")))
	var second_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("20260101-000000-test_loop-2.json")))
	var third_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("20260101-000000-test_loop-3.json")))
	assert_eq(int(first_data["index"]), 0)
	assert_eq(int(second_data["index"]), 1)
	assert_eq(int(third_data["index"]), 2)


## 18d-4 review fix #4: one race can write one file per recorded local human
## kart (split-screen), so rotation must evict whole races, not raw files —
## otherwise a race with more players evicts an older race's files one
## player at a time and can leave an older race's p2 file orphaned once its
## p1 file is gone.
func test_write_and_rotate_keeps_the_newest_20_races_worth_of_two_player_files() -> void:
	for race_index: int in range(22):
		var stamp: String = "%03d" % race_index
		var p1_error: Error = RaceTelemetryService.write_and_rotate(_directory, "%s-track-p1.json" % stamp, {"race": race_index, "player": 1}, 20)
		var p2_error: Error = RaceTelemetryService.write_and_rotate(_directory, "%s-track-p2.json" % stamp, {"race": race_index, "player": 2}, 20)
		assert_eq(p1_error, OK)
		assert_eq(p2_error, OK)

	var remaining: PackedStringArray = _list_json_files(_directory)
	assert_eq(remaining.size(), 40, "rotation must keep exactly 20 races worth of files (2 players each)")
	assert_false(FileAccess.file_exists(_directory.path_join("000-track-p1.json")), "the oldest race's p1 file must be evicted")
	assert_false(FileAccess.file_exists(_directory.path_join("000-track-p2.json")), "the oldest race's p2 file must be evicted with it, not orphaned")
	assert_false(FileAccess.file_exists(_directory.path_join("001-track-p1.json")))
	assert_false(FileAccess.file_exists(_directory.path_join("001-track-p2.json")))
	assert_true(FileAccess.file_exists(_directory.path_join("002-track-p1.json")), "the 20 newest races (002-021) must both survive")
	assert_true(FileAccess.file_exists(_directory.path_join("002-track-p2.json")))
	assert_true(FileAccess.file_exists(_directory.path_join("021-track-p1.json")))
	assert_true(FileAccess.file_exists(_directory.path_join("021-track-p2.json")))


## 18d-4 review fix #3: once every `<stem>-N.<ext>` suffix up to
## MAX_COLLISION_SUFFIX is taken, the write must be skipped (not clobber the
## last candidate tried) and every pre-existing file's contents must be
## untouched.
func test_write_and_rotate_skips_the_write_when_every_collision_suffix_is_taken() -> void:
	var base_error: Error = RaceTelemetryService.write_and_rotate(_directory, "20260101-000000-test_loop.json", {"who": "base"}, 100)
	assert_eq(base_error, OK)
	for suffix: int in range(2, RaceTelemetryService.MAX_COLLISION_SUFFIX + 2):
		var suffixed_error: Error = RaceTelemetryService.write_and_rotate(
			_directory, "20260101-000000-test_loop-%d.json" % suffix, {"who": "suffix-%d" % suffix}, 100
		)
		assert_eq(suffixed_error, OK)

	var exhausted_error: Error = RaceTelemetryService.write_and_rotate(_directory, "20260101-000000-test_loop.json", {"who": "exhausted"}, 100)

	assert_eq(exhausted_error, ERR_ALREADY_EXISTS, "the write must be skipped once every collision suffix is taken")
	var last_candidate_path: String = _directory.path_join("20260101-000000-test_loop-%d.json" % (RaceTelemetryService.MAX_COLLISION_SUFFIX + 1))
	var last_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(last_candidate_path))
	assert_eq(String(last_data["who"]), "suffix-%d" % (RaceTelemetryService.MAX_COLLISION_SUFFIX + 1), "the last candidate file must not be clobbered")


func test_disabled_setting_prevents_any_write() -> void:
	var service: RaceTelemetryService = RaceTelemetryService.new()
	service.telemetry_directory = _directory
	service.enabled_override = false
	add_child_autofree(service)

	EventBus.race_started.emit()
	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)

	assert_eq(_list_json_files(_directory).size(), 0, "a disabled/gated instance must never write telemetry")


func test_automation_mode_blocks_recording_on_the_real_ungated_gate() -> void:
	var previous_automation: bool = GameState.automation_mode
	GameState.automation_mode = true
	var service: RaceTelemetryService = RaceTelemetryService.new()
	service.telemetry_directory = _directory
	add_child_autofree(service)

	EventBus.race_started.emit()
	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)
	GameState.automation_mode = previous_automation

	assert_eq(_list_json_files(_directory).size(), 0, "GameState.automation_mode must block recording without enabled_override")


func test_tutorial_active_blocks_recording_on_the_real_ungated_gate() -> void:
	var previous_tutorial: bool = GameState.tutorial_active
	GameState.tutorial_active = true
	var service: RaceTelemetryService = RaceTelemetryService.new()
	service.telemetry_directory = _directory
	add_child_autofree(service)

	EventBus.race_started.emit()
	EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)
	GameState.tutorial_active = previous_tutorial

	assert_eq(_list_json_files(_directory).size(), 0, "GameState.tutorial_active must block recording without enabled_override")


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
	files.sort()
	return files


func _remove_directory(directory: String) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return
	for file_name: String in _list_json_files(directory):
		dir.remove(file_name)
	DirAccess.remove_absolute(directory)

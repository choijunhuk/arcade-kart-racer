extends GutTest

## Pure gating/recovery/identity tests for RaceTelemetryService (Phase 18d-3),
## plus the write_and_rotate file helper and the disabled-setting/automation/
## tutorial/headless recording gate on a real (test-directed) instance.

var _directory: String


func before_each() -> void:
	_directory = "user://test_telemetry_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_directory(_directory)


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

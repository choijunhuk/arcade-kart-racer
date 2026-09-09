extends GutTest

const GHOST_DIRECTORY: String = "user://phase12-unit-ghosts"
var _kart: KartController


func before_each() -> void:
	_kart = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(_kart)
	_kart.set_physics_process(false)
	DirAccess.remove_absolute(GHOST_DIRECTORY.path_join("unit_track.json"))


func after_each() -> void:
	DirAccess.remove_absolute(GHOST_DIRECTORY.path_join("unit_track.json"))


func test_input_frame_round_trip_preserves_every_edge_and_tick() -> void:
	var frame: InputFrame = _frame()
	var decoded: InputFrame = InputFrame.from_dict(JSON.parse_string(JSON.stringify(frame.to_dict())))
	assert_eq(decoded.to_dict(), frame.to_dict())


func test_ghost_json_round_trip_retains_initial_state_and_inputs() -> void:
	var source: GhostRecording = _recording()
	var result: GhostRecording = GhostRecording.from_dict(JSON.parse_string(JSON.stringify(source.to_dict())))
	assert_not_null(result)
	if result != null:
		assert_eq(result.frames, source.frames)
		assert_eq(result.initial_state, source.initial_state)
		assert_eq(result.lap_ticks, source.lap_ticks)


func test_ghost_replays_one_frame_per_tick_and_then_neutral_input() -> void:
	var recording: GhostRecording = _recording()
	var provider: GhostInputProvider = GhostInputProvider.new(recording)
	var first: InputFrame = provider.get_frame()
	assert_eq(first.to_dict(), _frame().to_dict())
	first.steer = 0.0
	assert_eq(float(recording.frames[0]["steer"]), 0.25)
	assert_eq(provider.get_frame().to_dict(), InputFrame.zero().to_dict())
	assert_eq(provider.cursor, 1)


func test_invalid_version_tick_rate_and_nonfinite_input_are_rejected() -> void:
	var data: Dictionary = _recording().to_dict()
	data["version"] = 99
	assert_null(GhostRecording.from_dict(data))
	data["version"] = GhostRecording.VERSION
	data["tick_rate"] = 30
	assert_null(GhostRecording.from_dict(data))
	data["tick_rate"] = GhostRecording.TICK_RATE
	data["frames"][0]["steer"] = NAN
	assert_null(GhostRecording.from_dict(data))


func test_malformed_snapshot_and_unknown_effect_are_rejected() -> void:
	var data: Dictionary = _recording().to_dict()
	data["initial_state"]["position"] = [0, "wrong", 0]
	assert_null(GhostRecording.from_dict(data))
	data = _recording().to_dict()
	data["frames"][0]["events"] = [{"type": "arbitrary_method"}]
	assert_null(GhostRecording.from_dict(data))


func test_best_ghost_persistence_refuses_a_slower_lap() -> void:
	var recording: GhostRecording = _recording()
	assert_eq(recording.save_best(GHOST_DIRECTORY), OK)
	assert_not_null(GhostRecording.load_best(&"unit_track", GHOST_DIRECTORY))
	assert_eq(recording.save_best(GHOST_DIRECTORY), ERR_ALREADY_EXISTS)
	assert_null(GhostRecording.load_best(&"different_track", GHOST_DIRECTORY))


func test_initial_speed_and_active_boost_are_restored() -> void:
	var physics: KartPhysics = _kart.get_node("KartPhysics") as KartPhysics
	physics.speed = 24.0
	physics.lateral = 2.0
	_kart.request_boost(_kart.tuning.start_boost_tier_two, &"start_boost")
	var data: Dictionary = KartReplayState.capture(_kart)
	physics.speed = 0.0
	physics.lateral = 0.0
	KartReplayState.restore(_kart, data)
	assert_almost_eq(_kart.get_speed(), 24.0, 0.00001)
	assert_almost_eq(_kart.get_lateral_speed(), 2.0, 0.00001)
	assert_true(_kart.is_boosting())
	assert_eq(_kart.get_boost_source(), &"start_boost")


func test_recorded_external_launch_is_applied_on_the_same_input_tick() -> void:
	var recording: GhostRecording = _recording()
	recording.frames[0]["events"] = [{"type": "launch", "velocity": [0.0, 12.0, -25.0]}]
	var provider: GhostInputProvider = GhostInputProvider.new(recording, _kart)
	provider.get_frame()
	assert_eq(_kart.get_state(), KartState.AIRBORNE)
	assert_almost_eq(_kart.get_speed(), 25.0, 0.00001)


func _recording() -> GhostRecording:
	var recording: GhostRecording = GhostRecording.new()
	recording.track_id = &"unit_track"
	recording.initial_state = KartReplayState.capture(_kart)
	recording.frames.append(_frame().to_dict())
	recording.progress.append(0.5)
	recording.lap_ticks = 1
	return recording


func _frame() -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 1.0
	frame.brake = 0.1
	frame.steer = 0.25
	frame.drift = true
	frame.drift_pressed = true
	frame.item = true
	frame.look_back = true
	frame.tick = 120
	return frame

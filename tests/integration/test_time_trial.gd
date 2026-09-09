extends GutTest

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const DIRECTORY: String = "user://phase12-integration-ghosts"
const SAVE_PATH: String = "user://phase12-time-trial-save.json"
const TIMEOUT_TICKS: int = 7200
const FIXED_DELTA: float = 1.0 / 60.0
var _save_path: String


func before_each() -> void:
	_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	GameState.reset_session()
	DirAccess.remove_absolute(DIRECTORY.path_join("test_loop.json"))


func after_each() -> void:
	SaveManager.save_path = _save_path
	get_tree().paused = false
	DirAccess.remove_absolute(DIRECTORY.path_join("test_loop.json"))
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".bak")


func test_time_trial_records_and_physically_replays_the_lap_within_one_tick() -> void:
	await _verify_recording_and_replay(1)


func test_flying_second_lap_restores_its_initial_speed_and_replays() -> void:
	await _verify_recording_and_replay(2)


func _verify_recording_and_replay(laps: int) -> void:
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	var config: RaceConfig = _config()
	config.laps = laps
	manager.configure(config, _driver)
	add_child_autofree(manager)
	var trial: TimeTrialGhost = manager.modes.time_trial
	assert_not_null(trial)
	if trial == null:
		return
	trial.ghost_directory = DIRECTORY
	trial.best = null
	assert_eq(manager.get_karts().size(), 1)
	assert_false((manager.get_node("ItemManager") as ItemManager).items_enabled)
	var positions: Dictionary[int, Vector3] = {}
	var observed_recording: GhostRecording
	for tick: int in range(TIMEOUT_TICKS):
		if manager.get_state() == RaceState.RACING:
			if observed_recording != trial._recording:
				positions.clear()
				observed_recording = trial._recording
			positions[trial._recording.frames.size()] = manager.get_karts()[0].global_position
		if manager.get_state() == RaceState.RESULTS:
			break
		await wait_physics_frames(1)
	assert_eq(manager.get_state(), RaceState.RESULTS)
	var recording: GhostRecording = GhostRecording.load_best(&"test_loop", DIRECTORY)
	assert_not_null(recording, "a completed best lap must create user://ghosts-style JSON")
	if recording == null:
		return
	assert_eq(trial.last_save_error, OK)
	if laps > 1:
		assert_gt(float(recording.initial_state["components"]["KartPhysics"]["speed"]), 5.0)
	var replay: GhostPlayback = GhostPlayback.new()
	add_child_autofree(replay)
	replay.setup(recording, manager.get_node("Track") as TrackRoot)
	assert_true(replay.kart.input_provider is GhostInputProvider)
	assert_eq(replay.kart.collision_layer, 0)
	assert_eq(replay.kart.collision_mask, 0)
	assert_eq((replay.kart.get_node("BumpArea") as Area3D).collision_layer, 0)
	assert_eq(manager.get_karts().size(), 1, "ghost never enters race standings")
	var max_position_error: float = 0.0
	for tick: int in range(recording.frames.size() + 120):
		await wait_physics_frames(1)
		replay.step(FIXED_DELTA)
		if positions.has(replay.ticks):
			max_position_error = maxf(max_position_error, replay.kart.global_position.distance_to(positions[replay.ticks]))
		if replay.finish_ticks >= 0:
			break
	print("GHOST_DETERMINISM recorded_ticks=%d replay_ticks=%d inputs=%d" % [recording.lap_ticks, replay.finish_ticks, recording.frames.size()])
	assert_lte(max_position_error, 0.01, "same-tick poses stay within one centimetre without pose correction")
	assert_gt(replay.finish_ticks, 0, "must cross all checkpoint volumes using replayed physics")
	assert_lte(absi(replay.finish_ticks - recording.lap_ticks), 1)


func test_time_trial_normalization_forces_no_ai_and_no_items() -> void:
	var config: RaceConfig = _config()
	config.kart_count = 8
	config.player_slot = -1
	config.items_enabled = true
	RaceConfigBuilder.normalize(config)
	assert_eq(config.kart_count, 1)
	assert_eq(config.player_slot, 0)
	assert_false(config.items_enabled)


func test_ghost_uses_private_recorded_gates_without_moving_the_live_track() -> void:
	var track: TrackRoot = (load("res://data/tracks/track_02.tres") as TrackData).scene.instantiate() as TrackRoot
	add_child_autofree(track)
	var source: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(source)
	source.set_physics_process(false)
	var recording: GhostRecording = GhostRecording.new()
	recording.initial_state = KartReplayState.capture(source)
	var replay: GhostPlayback = GhostPlayback.new()
	add_child_autofree(replay)
	replay.setup(recording, track)
	var movers: Array[MovingObstacle] = []
	for child: Node in track.get_node("MovingObstacles").get_children():
		if child is MovingObstacle:
			movers.append(child as MovingObstacle)
	var poses: Array[Array] = GhostWorldReplay.capture(movers)
	var original: Vector3 = movers[0].global_position
	movers[0].set_physics_process(false)
	movers[0].sync_to_physics = false
	movers[0].global_position += Vector3.RIGHT * 100.0
	replay.world_replay.apply_frame({"movers": poses})
	assert_eq(replay.world_replay.copies.size(), 2)
	assert_almost_eq(replay.world_replay.copies[0].global_position.distance_to(original), 0.0, 0.00001)
	assert_gt(movers[0].global_position.distance_to(original), 90.0)
	assert_eq(source.collision_mask & replay.world_replay.copies[0].collision_layer, 0)
	var motion: KartWorldMotion = replay.kart.get_node("WorldMotion") as KartWorldMotion
	assert_true(motion.get_collision_exceptions().has(movers[0]))


func _config() -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.race_mode = RaceConfig.RaceMode.TIME_TRIAL
	config.track = TrackData.new()
	config.track.id = &"test_loop"
	config.track.scene = load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene
	config.laps = 1
	return config


func _driver(kart: KartController, line: RacingLine) -> InputProvider:
	return ScriptedInputProvider.new(kart, line)

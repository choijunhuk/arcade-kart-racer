extends GutTest

const RACE_SCENE_PATH: String = "res://race/race.tscn"
const TEST_TRACK_PATH: String = "res://track/tracks/test_loop/test_loop.tscn"
const TICKS_PER_SECOND: int = 60
const COUNTDOWN_TIMEOUT_TICKS: int = 240
const RACE_TIMEOUT_TICKS: int = 7200
const PAUSE_OBSERVATION_TICKS: int = 30
const POSITION_EPSILON: float = 0.001

var _state_history: Array[int] = []


func before_each() -> void:
	_state_history.clear()
	if not EventBus.race_state_changed.is_connected(_on_race_state_changed):
		EventBus.race_state_changed.connect(_on_race_state_changed)


func after_each() -> void:
	get_tree().paused = false
	if EventBus.race_state_changed.is_connected(_on_race_state_changed):
		EventBus.race_state_changed.disconnect(_on_race_state_changed)


func test_race_scene_delegates_each_race_responsibility_to_a_child_node() -> void:
	var manager: Node = _make_race_manager()
	if manager == null:
		return
	assert_not_null(manager.get_node_or_null("LapTracker"))
	assert_not_null(manager.get_node_or_null("PositionTracker"))
	assert_not_null(manager.get_node_or_null("RespawnSystem"))
	assert_not_null(manager.get_node_or_null("KartCollisionResolver"))
	assert_not_null(manager.get_node_or_null("Countdown"))
	assert_not_null(manager.get_node_or_null("RaceResults"))
	assert_not_null(manager.get_node_or_null("Karts"))
	assert_not_null(manager.get_node_or_null("RaceCamera"))


func test_four_scripted_karts_complete_pause_results_and_restart_cycle() -> void:
	var manager: Node = _make_race_manager()
	if manager == null:
		return
	var config: RaceConfig = _make_test_config()
	manager.call("configure", config, _make_scripted_provider)
	add_child_autofree(manager)
	await wait_physics_frames(1)

	assert_eq(int(manager.call("get_state")), RaceState.COUNTDOWN)
	var karts: Array[KartController] = manager.call("get_karts") as Array[KartController]
	assert_eq(karts.size(), 4)
	for kart: KartController in karts:
		assert_eq(kart.get_state(), KartState.FROZEN)

	await _wait_for_state(manager, RaceState.RACING, COUNTDOWN_TIMEOUT_TICKS)
	assert_eq(int(manager.call("get_state")), RaceState.RACING)
	manager.call("pause_race")
	var paused_position: Vector3 = karts[0].global_position
	await wait_physics_frames(PAUSE_OBSERVATION_TICKS)
	assert_almost_eq(karts[0].global_position.distance_to(paused_position), 0.0, POSITION_EPSILON)
	manager.call("resume_race")

	await _wait_for_state(manager, RaceState.RESULTS, RACE_TIMEOUT_TICKS)
	assert_eq(int(manager.call("get_state")), RaceState.RESULTS)
	assert_true(_state_history.has(RaceState.FINISHING))
	assert_true(_state_history.has(RaceState.RESULTS))
	var entries: Array = manager.call("get_results") as Array
	assert_eq(entries.size(), 4)

	manager.call("restart")
	await wait_physics_frames(2)
	assert_eq(int(manager.call("get_state")), RaceState.COUNTDOWN)
	var restarted_karts: Array[KartController] = manager.call("get_karts") as Array[KartController]
	assert_eq(restarted_karts.size(), 4)
	var tracker: LapTracker = manager.get_node("LapTracker") as LapTracker
	for kart: KartController in restarted_karts:
		assert_eq(tracker.get_lap(kart), 0)


func _make_race_manager() -> Node:
	var exists: bool = ResourceLoader.exists(RACE_SCENE_PATH)
	assert_true(exists, "race.tscn must exist")
	return (load(RACE_SCENE_PATH) as PackedScene).instantiate() if exists else null


func _make_test_config() -> RaceConfig:
	var track_data: TrackData = TrackData.new()
	track_data.id = &"test_loop"
	track_data.display_name = "Test Loop"
	track_data.scene = load(TEST_TRACK_PATH) as PackedScene
	track_data.laps_default = 1
	var config: RaceConfig = RaceConfig.new()
	config.track = track_data
	config.laps = 1
	config.kart_count = 4
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.set("player_slot", 0)
	return config


func _make_scripted_provider(kart: KartController, line: RacingLine) -> InputProvider:
	var provider: ScriptedInputProvider = ScriptedInputProvider.new(kart, line)
	provider.set_drift_on_corners(true)
	return provider


func _wait_for_state(manager: Node, target_state: int, max_ticks: int) -> void:
	for _tick: int in range(max_ticks):
		if int(manager.call("get_state")) == target_state:
			return
		await wait_physics_frames(1)


func _on_race_state_changed(_old_state: int, new_state: int) -> void:
	_state_history.append(new_state)

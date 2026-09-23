extends GutTest

## 19-D item 2: pre-countdown flyover rules, the Countdown pre-roll/skip and
## the camera/HUD finish presentation (never Engine.time_scale).

var _ticks: Array[int] = []
var _intro_events: Array[String] = []
var _saved: Dictionary = {}


func before_each() -> void:
	_ticks.clear()
	_intro_events.clear()
	_saved = {
		"automation": GameState.automation_mode, "networked": GameState.is_networked,
		"tutorial": GameState.tutorial_active,
		"setting": SettingsManager.get_setting(&"gameplay", &"race_intro", true),
	}
	GameState.automation_mode = false
	GameState.is_networked = false
	GameState.tutorial_active = false
	SettingsManager.set_setting(&"gameplay", &"race_intro", true)
	EventBus.countdown_tick.connect(_on_tick)
	EventBus.race_intro_started.connect(_on_intro_started)
	EventBus.race_intro_finished.connect(_on_intro_finished)


func after_each() -> void:
	GameState.automation_mode = _saved["automation"]
	GameState.is_networked = _saved["networked"]
	GameState.tutorial_active = _saved["tutorial"]
	SettingsManager.set_setting(&"gameplay", &"race_intro", _saved["setting"])
	EventBus.countdown_tick.disconnect(_on_tick)
	EventBus.race_intro_started.disconnect(_on_intro_started)
	EventBus.race_intro_finished.disconnect(_on_intro_finished)
	Engine.time_scale = 1.0


func _on_tick(value: int) -> void:
	_ticks.append(value)


func _on_intro_started(_seconds: float) -> void:
	_intro_events.append("started")


func _on_intro_finished() -> void:
	_intro_events.append("finished")


func _config(mode: RaceConfig.RaceMode = RaceConfig.RaceMode.SINGLE_RACE) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.race_mode = mode
	config.player_slot = 0
	return config


func test_single_race_gets_the_full_flyover() -> void:
	assert_eq(RaceIntro.seconds_for(_config()), RaceIntro.FULL_SECONDS)
	assert_between(RaceIntro.FULL_SECONDS, 2.0, 3.0, "spec: 2-3 s flyover")


func test_time_trial_flyover_is_short() -> void:
	var seconds: float = RaceIntro.seconds_for(_config(RaceConfig.RaceMode.TIME_TRIAL))
	assert_gt(seconds, 0.0)
	assert_lt(seconds, RaceIntro.FULL_SECONDS)


func test_online_tutorial_automation_setting_and_all_ai_have_no_flyover() -> void:
	GameState.is_networked = true
	assert_eq(RaceIntro.seconds_for(_config()), 0.0, "online")
	GameState.is_networked = false
	GameState.tutorial_active = true
	assert_eq(RaceIntro.seconds_for(_config()), 0.0, "tutorial")
	GameState.tutorial_active = false
	GameState.automation_mode = true
	assert_eq(RaceIntro.seconds_for(_config()), 0.0, "automation/sims")
	GameState.automation_mode = false
	SettingsManager.set_setting(&"gameplay", &"race_intro", false)
	assert_eq(RaceIntro.seconds_for(_config()), 0.0, "settings toggle")
	SettingsManager.set_setting(&"gameplay", &"race_intro", true)
	var observer: RaceConfig = _config()
	observer.player_slot = -1
	assert_eq(RaceIntro.seconds_for(observer), 0.0, "all-AI observer")
	assert_eq(RaceConfig.new().intro_seconds, 0.0, "configs built outside menus (net, tests) default to none")


func test_countdown_holds_tick_three_for_the_intro_then_counts_down() -> void:
	var countdown: Countdown = _make_countdown()
	countdown.start(1.0)
	assert_true(countdown.is_intro_active())
	assert_eq(_ticks, [] as Array[int], "no 3 while the flyover runs")
	assert_eq(_intro_events, ["started"])
	assert_gt(countdown.get_phase_seconds(), 3.0 * countdown._tuning.countdown_step_seconds)
	assert_false(countdown.advance(0.5))
	assert_eq(_ticks.size(), 0)
	assert_false(countdown.advance(0.5))
	assert_eq(_ticks, [3] as Array[int])
	assert_eq(_intro_events, ["started", "finished"])
	assert_false(countdown.is_intro_active())


func test_skip_intro_starts_the_countdown_immediately() -> void:
	var countdown: Countdown = _make_countdown()
	countdown.start(2.6)
	countdown.skip_intro()
	assert_eq(_ticks, [3] as Array[int])
	assert_eq(_intro_events, ["started", "finished"])
	countdown.skip_intro()
	assert_eq(_ticks, [3] as Array[int], "skip is idempotent")


func test_accept_input_skips_the_intro() -> void:
	var countdown: Countdown = _make_countdown()
	countdown.start(2.6)
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	countdown._unhandled_input(event)
	assert_false(countdown.is_intro_active())
	assert_eq(_ticks, [3] as Array[int])


func test_zero_intro_keeps_the_legacy_immediate_three() -> void:
	var countdown: Countdown = _make_countdown()
	countdown.start()
	assert_eq(_ticks, [3] as Array[int])
	assert_eq(_intro_events.size(), 0)


func test_intro_pose_sweeps_from_front_high_to_the_chase_pose() -> void:
	var kart_position: Vector3 = Vector3(5.0, 1.0, -3.0)
	var start: Vector3 = CameraCinematics.intro_pose(kart_position, Vector3.FORWARD, 0.0, 6.0, 2.5)
	assert_gt((start - kart_position).dot(Vector3.FORWARD), 10.0, "starts ahead of the grid")
	assert_gt(start.y - kart_position.y, 10.0, "starts high")
	var end: Vector3 = CameraCinematics.intro_pose(kart_position, Vector3.FORWARD, 1.0, 6.0, 2.5)
	assert_almost_eq(end.distance_to(kart_position - Vector3.FORWARD * 6.0 + Vector3.UP * 2.5), 0.0, 0.01)


func test_finish_pose_holds_for_the_beat_then_orbits() -> void:
	var hold: Vector3 = Vector3(0.0, 3.0, 8.0)
	var kart_position: Vector3 = Vector3.ZERO
	assert_eq(CameraCinematics.finish_pose(kart_position, Vector3.FORWARD, 0.3, hold), hold)
	var late: Vector3 = CameraCinematics.finish_pose(kart_position, Vector3.FORWARD, 5.0, hold)
	var flat: Vector3 = Vector3(late.x, 0.0, late.z)
	assert_almost_eq(flat.length(), CameraCinematics.FINISH_ORBIT_RADIUS, 0.05)


func test_player_finish_starts_the_camera_orbit_without_touching_time_scale() -> void:
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(kart)
	var camera: RaceCamera = (load("res://camera/race_camera.tscn") as PackedScene).instantiate() as RaceCamera
	add_child_autofree(camera)
	camera.set_target(kart)
	var scale_before: float = Engine.time_scale
	EventBus.kart_finished.emit(kart, 42.0)
	assert_eq(camera.get_cinematic_mode(), CameraCinematics.Mode.FINISH)
	await wait_process_frames(10)
	assert_eq(Engine.time_scale, scale_before, "finish presentation never slows the engine")
	camera.set_target(kart)
	assert_eq(camera.get_cinematic_mode(), CameraCinematics.Mode.NONE, "restart clears it")


func test_podium_finish_celebrates_and_other_ranks_stay_plain() -> void:
	assert_true(FinishCelebration.is_podium(1))
	assert_true(FinishCelebration.is_podium(3))
	assert_false(FinishCelebration.is_podium(4))
	var celebration: FinishCelebration = FinishCelebration.new()
	celebration.size = Vector2(1280.0, 720.0)
	add_child_autofree(celebration)
	celebration.celebrate(HudReadout.GOLD)
	assert_gt(celebration.get_child_count(), 1, "confetti plus firework bursts")
	assert_eq(Engine.time_scale, 1.0)


func _make_countdown() -> Countdown:
	var countdown: Countdown = Countdown.new()
	add_child_autofree(countdown)
	countdown.setup(load("res://data/tuning/race_default.tres") as RaceTuning, [])
	return countdown

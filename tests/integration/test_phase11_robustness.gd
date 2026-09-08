extends GutTest

const RACE: PackedScene = preload("res://race/race.tscn")
const LOOP: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const SAVE_PATH: String = "user://phase11_robust_save.json"
const SETTINGS_PATH: String = "user://phase11_robust_settings.cfg"
const MAX_TICKS: int = 2400
const SPAM_COUNT: int = 30

var _save_path: String
var _settings_path: String
var _settings_before: Dictionary


func before_each() -> void:
	_save_path = SaveManager.save_path
	_settings_path = SettingsManager.settings_path
	_settings_before = SettingsManager.load_settings()
	SaveManager.save_path = SAVE_PATH
	SettingsManager.settings_path = SETTINGS_PATH


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	# Restore values through an isolated file before restoring the real path.
	SettingsManager.save_settings(_settings_before)
	SettingsManager.settings_path = _settings_path
	SaveManager.save_path = _save_path
	for path: String in [SAVE_PATH, SAVE_PATH + ".bak", SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func test_corrupt_save_and_settings_boot_real_main_menu() -> void:
	_write(SAVE_PATH, "{corrupt")
	_write(SAVE_PATH + ".bak", "[]")
	# ConfigFile.parse reports malformed text as an engine error; expected here.
	_write(SETTINGS_PATH, "[broken")
	var settings: Dictionary = SettingsManager.load_settings()
	assert_eq(settings["video"]["resolution"], Vector2i(1600, 900))
	assert_push_warning("Settings file could not be loaded")
	assert_engine_error_count(1)
	assert_eq(SaveManager.load_data()["version"], SaveManagerService.CURRENT_VERSION)
	var boot: Node = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(boot)
	await wait_process_frames(2)
	assert_true((boot.get_node("MainMenu/Panel/VBox/PlayButton") as Button).has_focus())
	assert_push_error_count(0)


func test_valid_json_with_corrupt_save_field_types_recovers() -> void:
	_write(SAVE_PATH, '{"version":1,"best_laps":[],"best_positions":"bad","last_selection":null}')
	var data: Dictionary = SaveManager.load_data()
	assert_true(data["best_laps"] is Dictionary)
	assert_true(data["best_positions"] is Dictionary)
	assert_true(data["last_selection"] is Dictionary)
	assert_eq(SaveManager.get_best_lap_ms(&"missing"), -1)
	assert_eq(SaveManager.record_race_result(&"track", 1000, 1), OK)


func test_valid_config_with_wrong_scalar_and_remap_types_recovers() -> void:
	_write(SETTINGS_PATH, '[audio]\nmaster=Vector2(1,2)\n[controls]\nremaps=7\ndeadzone="bad"\n[video]\nrender_scale=[]\n')
	var data: Dictionary = SettingsManager.load_settings()
	assert_eq(data["audio"]["master"], 1.0)
	assert_true(data["controls"]["remaps"] is Dictionary)
	assert_eq(data["controls"]["deadzone"], 0.2)
	assert_push_error_count(0)
	assert_engine_error_count(0)


func test_missing_gamepad_still_allows_keyboard_acceleration() -> void:
	var disconnected: PlayerInputProvider = PlayerInputProvider.new(99)
	assert_eq(disconnected.get_frame().throttle, 0.0)
	var provider: PlayerInputProvider = PlayerInputProvider.new()
	Input.action_press(InputActions.ACCELERATE)
	var frame: InputFrame = provider.get_frame()
	Input.action_release(InputActions.ACCELERATE)
	assert_gt(frame.throttle, 0.0)
	assert_eq(frame.brake, 0.0)


func test_focus_loss_pauses_countdown_and_focus_return_does_not_resume() -> void:
	var race: RaceManager = _make_race(1, 0)
	get_tree().root.focus_exited.emit()
	assert_eq(race.get_state(), RaceState.PAUSED)
	get_tree().root.focus_entered.emit()
	assert_true(get_tree().paused)
	race.resume_race()
	assert_eq(race.get_state(), RaceState.COUNTDOWN)


func test_focus_loss_pauses_racing_and_stops_motion() -> void:
	var race: RaceManager = _make_race(1, 0)
	await _wait_state(race, RaceState.RACING)
	get_tree().root.focus_exited.emit()
	var position: Vector3 = race.get_karts()[0].global_position
	await wait_process_frames(3)
	assert_eq(race.get_state(), RaceState.PAUSED)
	assert_eq(race.get_karts()[0].global_position, position)


func test_pause_spam_preserves_state_and_emits_go_only_once() -> void:
	var race: RaceManager = _make_race(1, 0)
	await _wait_state(race, RaceState.RACING)
	watch_signals(EventBus)
	for _index: int in range(SPAM_COUNT):
		race.pause_race()
		race.pause_race()
		race.resume_race()
		race.resume_race()
	assert_eq(race.get_state(), RaceState.RACING)
	assert_false(get_tree().paused)
	assert_signal_not_emitted(EventBus, "race_started")
	assert_push_error_count(0)


func test_restart_during_countdown_clears_karts_and_pending_go() -> void:
	var race: RaceManager = _make_race(2, 0)
	var old_kart: WeakRef = weakref(race.get_karts()[0])
	await wait_physics_frames(2)
	race.restart()
	assert_null(old_kart.get_ref())
	assert_eq(race.get_state(), RaceState.COUNTDOWN)
	var tracker: LapTracker = race.get_node("LapTracker") as LapTracker
	assert_eq(tracker.get_lap(race.get_karts()[0]), 0)
	assert_eq(race.get_results().size(), 0)
	watch_signals(EventBus)
	await _wait_state(race, RaceState.RACING)
	assert_signal_emit_count(EventBus, "race_started", 1)
	assert_push_error_count(0)


func test_single_player_no_ai_completes_race() -> void:
	var race: RaceManager = _make_race(1, 0)
	Engine.time_scale = 4.0
	await _wait_state(race, RaceState.RESULTS)
	assert_eq(race.get_results().size(), 1)
	assert_gt(race.get_results()[0].total_time_seconds, 0.0)


func test_zero_players_all_ai_completes_race() -> void:
	var race: RaceManager = _make_race(2, -1)
	Engine.time_scale = 4.0
	await _wait_state(race, RaceState.RESULTS)
	assert_eq(race.get_results().size(), 2)
	for entry: RaceResults.Entry in race.get_results():
		assert_gt(entry.total_time_seconds, 0.0)


func test_quit_to_menu_during_finishing_releases_race() -> void:
	# Preserve the GUT root while the real transition frees the race scene.
	var original_scene: Node = get_tree().current_scene
	var race: RaceManager = _make_race(1, 0, true)
	get_tree().current_scene = race
	Engine.time_scale = 4.0
	await _wait_state(race, RaceState.FINISHING)
	var old_race: WeakRef = weakref(race)
	race.back_to_menu()
	for _frame: int in range(MAX_TICKS):
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main.tscn":
			break
		await get_tree().process_frame
	assert_null(old_race.get_ref())
	var menu: Node = get_tree().current_scene
	assert_eq(menu.scene_file_path, "res://scenes/main.tscn")
	if menu != original_scene:
		menu.free()
	get_tree().current_scene = original_scene
	assert_false(get_tree().paused)
	assert_push_error_count(0)


func test_mixed_roster_restarts_without_mutating_shared_kart_data() -> void:
	var config: RaceConfig = _config(3, -1)
	config.kart_roster = [preload("res://data/karts/light.tres"), preload("res://data/karts/medium.tres"), preload("res://data/karts/heavy.tres")]
	var race: RaceManager = RACE.instantiate() as RaceManager
	race.configure(config)
	add_child_autofree(race)
	var light_speed: float = config.kart_roster[0].max_speed
	race.restart()
	for slot: int in range(3):
		assert_eq(race.get_karts()[slot].get_kart_data().id, config.kart_roster[slot].id)
	assert_eq(config.kart_roster[0].max_speed, light_speed)


func _make_race(count: int, player_slot: int, root_child: bool = false) -> RaceManager:
	var race: RaceManager = RACE.instantiate() as RaceManager
	race.configure(_config(count, player_slot), _provider)
	if root_child:
		get_tree().root.add_child(race)
		autofree(race)
	else:
		add_child_autofree(race)
	return race


func _config(count: int, player_slot: int) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.track = TrackData.new()
	config.track.scene = LOOP
	config.track.id = &"test_loop"
	config.laps = 1
	config.kart_count = count
	config.player_slot = player_slot
	config.seed = 1101
	return config


func _provider(kart: KartController, line: RacingLine) -> InputProvider:
	return ScriptedInputProvider.new(kart, line)


func _wait_state(race: RaceManager, state: int) -> void:
	for _tick: int in range(MAX_TICKS):
		if race.get_state() == state:
			return
		await get_tree().physics_frame
	assert_eq(race.get_state(), state)


func _write(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func test_hud_anchors_follow_viewport_resize_during_racing() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var race: RaceManager = RACE.instantiate() as RaceManager
	race.configure(_config(1, 0), _provider)
	viewport.add_child(race)
	await _wait_state(race, RaceState.RACING)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		viewport.size = dimensions
		await wait_process_frames(3)
		var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(dimensions))
		for path: String in ["PositionPanel", "ItemPanel", "Minimap", "Speedometer", "DriftMeter"]:
			var control: Control = race.get_node("HUD/" + path) as Control
			assert_true(bounds.encloses(control.get_global_rect()), "%s remains visible at %s" % [path, dimensions])
		assert_eq(race.get_state(), RaceState.RACING)
	assert_push_error_count(0)


func test_fullscreen_setting_toggle_preserves_live_race() -> void:
	var race: RaceManager = _make_race(1, 0)
	await _wait_state(race, RaceState.RACING)
	for enabled: bool in [true, false, true, false]:
		SettingsManager.set_setting(&"video", &"fullscreen", enabled)
		await wait_process_frames(2)
		assert_eq(SettingsManager.get_setting(&"video", &"fullscreen"), enabled)
		assert_eq(race.get_state(), RaceState.RACING)
	# Native window mode is separately checked by windowed QA; headless has no OS window.
	assert_push_error_count(0)


func test_corrupt_remap_entries_preserve_default_actions() -> void:
	var before: Array[InputEvent] = InputMap.action_get_events(InputActions.ACCELERATE)
	_write(SETTINGS_PATH, '[controls]\nremaps={"accelerate":42,"brake":["bad",{"type":"key","keycode":[]}]}\n')
	SettingsManager.load_settings()
	assert_eq(InputMap.action_get_events(InputActions.ACCELERATE).size(), before.size())
	assert_gt(InputMap.action_get_events(InputActions.BRAKE).size(), 0)
	assert_engine_error_count(0)


func test_all_ai_observer_keeps_running_after_focus_loss() -> void:
	var race: RaceManager = _make_race(1, -1)
	get_tree().root.focus_exited.emit()
	assert_eq(race.get_state(), RaceState.COUNTDOWN)
	assert_false(get_tree().paused)


func test_hairpin_checkpoints_span_both_racing_lanes() -> void:
	var track: TrackRoot = preload("res://track/tracks/test_hairpin/test_hairpin.tscn").instantiate() as TrackRoot
	add_child_autofree(track)
	var body: CharacterBody3D = CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.6, 0.6, 2.2)
	collision.shape = box
	body.add_child(collision)
	add_child_autofree(body)
	for checkpoint: Checkpoint in track.get_checkpoints():
		var line: RacingLine = track.get_racing_line()
		for lane: float in [-3.0, 3.0]:
			body.global_position = checkpoint.global_position + line.right_at(checkpoint.offset) * lane
			await wait_physics_frames(3)
			assert_true(checkpoint.overlaps_body(body), "%s must span lane %.1f" % [checkpoint.name, lane])


func test_incomplete_key_remap_does_not_remove_keyboard_fallback() -> void:
	var count: int = InputMap.action_get_events(InputActions.ACCELERATE).size()
	_write(SETTINGS_PATH, '[controls]\nremaps={"accelerate":[{"type":"key"}]}\n')
	SettingsManager.load_settings()
	var bindings: Array[InputEvent] = InputMap.action_get_events(InputActions.ACCELERATE)
	assert_eq(bindings.size(), count)
	assert_true(bindings.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).physical_keycode != 0))


func test_out_of_range_deadzone_does_not_break_settings_application() -> void:
	_write(SETTINGS_PATH, '[controls]\ndeadzone=5.0\n')
	SettingsManager.load_settings()
	assert_gte(InputMap.action_get_deadzone(InputActions.ACCELERATE), 0.0)
	assert_lte(InputMap.action_get_deadzone(InputActions.ACCELERATE), 1.0)
	assert_engine_error_count(0)

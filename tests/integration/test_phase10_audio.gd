extends GutTest

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const TRACK_SCENE: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://ui/menus/settings_menu.tscn")
const ITEM: ItemData = preload("res://data/items/rocket_dart.tres")
const EPSILON: float = 0.001
const COUNTDOWN_TICKS: int = 240
const FULL_RACE_TICKS: int = 7200
const TEST_SETTINGS_PATH: String = "user://phase10_settings_test.cfg"
const DRIFT_DT: float = 1.0 / 60.0
const DRIFT_SPEED: float = 18.0

var _plays: Array[StringName] = []
var _tracks: Array[StringName] = []
var _settings: Dictionary
var _settings_path: String


func before_each() -> void:
	_plays.clear()
	_tracks.clear()
	_settings = SettingsManager.load_settings()
	_settings_path = SettingsManager.settings_path
	SettingsManager.settings_path = TEST_SETTINGS_PATH
	AudioManager.pool.stop_sfx()
	AudioManager.stop_bgm(0.0)
	AudioManager.sfx_played.connect(_spy_sfx)
	AudioManager.bgm_changed.connect(_spy_bgm)


func after_each() -> void:
	get_tree().paused = false
	AudioManager.sfx_played.disconnect(_spy_sfx)
	AudioManager.bgm_changed.disconnect(_spy_bgm)
	AudioManager.pool.stop_sfx()
	AudioManager.stop_bgm(0.0)
	AudioManager.set_final_lap(false)
	AudioManager.set_music_ducked(false)
	SettingsManager.save_settings(_settings)
	SettingsManager.settings_path = _settings_path
	SettingsManager.load_settings()
	DirAccess.remove_absolute(TEST_SETTINGS_PATH)


func test_race_countdown_requests_exactly_three_beeps_and_one_go() -> void:
	var race: RaceManager = _race(1, 1)
	await _wait_state(race, RaceState.RACING, COUNTDOWN_TICKS)
	assert_eq(race.get_state(), RaceState.RACING)
	assert_eq(_plays.count(&"countdown"), 3)
	assert_eq(_plays.count(&"go"), 1)
	race.pause_race()
	race.resume_race()
	assert_eq(_plays.count(&"go"), 1, "resume cannot repeat GO")


func test_real_menu_race_results_state_machine_switches_bgm() -> void:
	var menu: MainMenu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await wait_process_frames(2)
	assert_eq(AudioManager.bgm.current_id, &"menu")
	menu.free()
	var race: RaceManager = _race(1, 1, true)
	assert_eq(AudioManager.bgm.current_id, &"race")
	await _wait_state(race, RaceState.RESULTS, FULL_RACE_TICKS)
	assert_eq(race.get_state(), RaceState.RESULTS)
	assert_eq(AudioManager.bgm.current_id, &"results")
	assert_eq(_tracks, [&"menu", &"race", &"results"])
	assert_eq(_plays.count(&"finish"), 1)
	race.restart()
	assert_eq(AudioManager.bgm.current_id, &"race")
	assert_eq(AudioManager.bgm.pitch_scale, 1.0)


func test_local_drift_tier_and_all_kart_feedback_signals_play_sounds() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.set_physics_process(false)
	await wait_process_frames(1)
	for tier: int in range(1, 4):
		AudioManager.pool.release_owner(kart.get_instance_id())
		kart.drift_controller.drift_tier_changed.emit(tier)
		assert_true(_plays.has(StringName("drift_tier_%d" % tier)))
	var physics: KartPhysics = kart.get_node("KartPhysics") as KartPhysics
	var hit: HitReactor = kart.get_node("HitReactor") as HitReactor
	AudioManager.pool.release_owner(kart.get_instance_id())
	physics.wall_impacted.emit()
	physics.landed.emit(-10.0)
	kart.launched.emit()
	assert_true(_plays.has(&"impact_wall"))
	assert_true(_plays.has(&"landing"))
	assert_true(_plays.has(&"jump"))
	for type: int in [HitReactor.HitType.SPIN_OUT, HitReactor.HitType.TUMBLE, HitReactor.HitType.SQUASH]:
		hit.hit_started.emit(type)
	assert_true(_plays.has(&"hit_spin"))
	assert_true(_plays.has(&"hit_tumble"))
	assert_true(_plays.has(&"hit_squash"))
	kart.boost_controller.boost_started.emit(BoostSpecData.new())
	assert_true(_plays.has(&"boost"))


func test_player_roulette_signals_emit_pickup_tick_and_stop() -> void:
	var race: RaceManager = _race(1, 2)
	await wait_process_frames(1)
	var kart: KartController = race.get_karts()[0]
	kart.item_slot.begin_roulette(ITEM)
	kart.item_slot.tick_roulette(ItemSlot.AUDIO_TICK_SECONDS)
	kart.item_slot.tick_roulette(ItemRoulette.DURATION_SECONDS)
	assert_true(_plays.has(&"item_pickup"))
	assert_true(_plays.has(&"roulette_tick"))
	assert_true(_plays.has(&"roulette_stop"))


func test_real_drift_charge_transition_emits_a_chime_without_audio_writing_physics() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.set_physics_process(false)
	await wait_process_frames(1)
	var frame: InputFrame = InputFrame.zero()
	frame.steer = 1.0
	frame.drift = true
	frame.drift_pressed = true
	kart.drift_controller.step(frame, DRIFT_SPEED, true, 0.0, 1.0, false, DRIFT_DT)
	frame.drift_pressed = false
	for _tick: int in range(90):
		kart.drift_controller.step(frame, DRIFT_SPEED, true, 0.0, 1.0, false, DRIFT_DT)
	assert_eq(_plays.count(&"drift_tier_1"), 1)
	var before_speed: float = kart.get_speed()
	(kart.get_node("KartAudio") as KartAudio)._process(DRIFT_DT)
	assert_eq(kart.get_speed(), before_speed)


func test_player_terrain_and_lateral_ratio_drive_filter_and_squeal_gain() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	var audio: KartAudio = kart.get_node("KartAudio") as KartAudio
	audio.set_player_audio(true)
	add_child_autofree(kart)
	kart.set_physics_process(false)
	await wait_process_frames(1)
	var physics: KartPhysics = kart.get_node("KartPhysics") as KartPhysics
	physics.grounded = true
	physics.lateral = kart.kart_data.max_speed * 0.5
	kart._current_terrain_id = &"grass"
	audio._process(DRIFT_DT)
	assert_true(AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(&"Engine"), 0))
	assert_not_null(audio._squeal)
	assert_almost_eq(audio._squeal.flat.volume_db, audio._squeal.base_volume_db + linear_to_db(0.5), EPSILON)
	physics.lateral = 0.0
	kart._current_terrain_id = &"asphalt"
	audio._process(DRIFT_DT)
	assert_false(audio._squeal.active)
	assert_false(AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(&"Engine"), 0))


func test_item_fire_hit_threat_and_player_only_rank_feedback() -> void:
	var race: RaceManager = _race(2, 3)
	await _wait_state(race, RaceState.RACING, COUNTDOWN_TICKS)
	var player: KartController = race.get_karts()[0]
	var ai: KartController = race.get_karts()[1]
	AudioManager.pool.stop_sfx()
	_plays.clear()
	EventBus.position_changed.emit(ai, 2, 1)
	EventBus.position_changed.emit(player, 2, 1)
	EventBus.position_changed.emit(player, 1, 2)
	assert_eq(_plays, [&"position_up", &"position_down"])
	EventBus.threat_warning.emit(player, &"storm_beacon", 3.0)
	assert_true(_plays.has(&"threat_warning"))
	for id: StringName in [&"rocket_dart", &"hunter_drone", &"spike_mine", &"nitro_can", &"aegis_bubble", &"pulse_blast", &"storm_beacon"]:
		AudioManager.pool.stop_sfx()
		EventBus.item_used.emit(player, id)
		EventBus.item_hit.emit(player, ai, id)
		assert_true(_plays.has(StringName("%s_fire" % id)))
		assert_true(_plays.has(StringName("%s_hit" % id)))


func test_lap_stingers_and_guarded_pitch_update_immediately() -> void:
	var race: RaceManager = _race(1, 3)
	var kart: KartController = race.get_karts()[0]
	SettingsManager.update_setting(&"audio", &"final_lap_pitch", true)
	EventBus.lap_completed.emit(kart, 1, 10.0)
	assert_true(_plays.has(&"lap"))
	assert_eq(AudioManager.bgm.pitch_scale, 1.0)
	EventBus.lap_completed.emit(kart, 2, 20.0)
	assert_true(_plays.has(&"final_lap"))
	assert_almost_eq(AudioManager.bgm.pitch_scale, 1.03, EPSILON)
	SettingsManager.update_setting(&"audio", &"final_lap_pitch", false)
	assert_eq(AudioManager.bgm.pitch_scale, 1.0)


func test_settings_sliders_immediately_mute_all_four_buses() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate() as SettingsMenu
	add_child_autofree(menu)
	for name: String in ["Master", "Music", "Sfx", "Engine"]:
		var slider: HSlider = menu.get_node("Panel/VBox/Tabs/Audio/%sSlider" % name) as HSlider
		slider.value = 0.5
		var bus_name: StringName = &"SFX" if name == "Sfx" else StringName(name)
		assert_almost_eq(AudioManager.get_bus_volume(bus_name), 0.5, EPSILON)
		slider.value = 0.0
		assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name)))
	assert_not_null(menu.get_node_or_null("Panel/VBox/Tabs/Audio/FinalLapPitchToggle"))


func test_ui_adapter_handles_dynamic_buttons_and_back_once() -> void:
	var root: Control = Control.new()
	add_child_autofree(root)
	UiAudio.attach(root)
	var button: Button = Button.new()
	button.name = &"BackButton"
	root.add_child(button)
	button.focus_entered.emit()
	button.pressed.emit()
	assert_eq(_plays, [&"menu_move", &"menu_back"])
	button.disabled = true
	button.pressed.emit()
	assert_eq(_plays.size(), 2)


func test_eight_karts_keep_exact_player_budget_with_owned_loops_and_cleanup() -> void:
	var race: RaceManager = _race(8, 1)
	await _wait_state(race, RaceState.RACING, COUNTDOWN_TICKS)
	var karts: Array[KartController] = race.get_karts()
	for _tick: int in range(120):
		for kart: KartController in karts:
			kart.drift_controller.drift_tier_changed.emit(1)
			assert_lte(AudioManager.pool.count_owner(kart.get_instance_id()), 3)
		assert_lte(AudioManager.pool.count_active(true), 16)
		assert_lte(AudioManager.pool.count_active(false), 8)
		await wait_physics_frames(1)
	assert_eq(AudioManager.pool.get_child_count(), 24)
	var player_voice: AudioVoice = (karts[0].get_node("KartAudio") as KartAudio)._engine
	assert_not_null(player_voice)
	assert_not_null(player_voice.flat)
	assert_eq(player_voice.flat.bus, &"Engine")
	var ai_voice: AudioVoice = (karts[1].get_node("KartAudio") as KartAudio)._engine
	assert_not_null(ai_voice.spatial)
	assert_push_error_count(0)
	race.free()
	assert_eq(AudioManager.pool.count_active(true), 0)
	assert_lte(AudioManager.pool.count_active(false), 2, "only reserved music may survive teardown")


func _race(count: int, laps: int, scripted: bool = false) -> RaceManager:
	var config: RaceConfig = RaceConfig.new()
	config.track = TrackData.new()
	config.track.id = &"phase10_test_loop"
	config.track.scene = TRACK_SCENE
	config.kart_count = count
	config.laps = laps
	config.items_enabled = false
	config.player_slot = 0
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	race.configure(config, _provider if scripted else Callable())
	add_child_autofree(race)
	return race


func _provider(kart: KartController, line: RacingLine) -> InputProvider:
	return ScriptedInputProvider.new(kart, line)


func _wait_state(race: RaceManager, state: int, max_ticks: int) -> void:
	for _tick: int in range(max_ticks):
		if race.get_state() == state:
			return
		await wait_physics_frames(1)


func _spy_sfx(id: StringName, _spatial: bool, _priority: int, _pitch: float) -> void:
	_plays.append(id)


func _spy_bgm(id: StringName) -> void:
	_tracks.append(id)

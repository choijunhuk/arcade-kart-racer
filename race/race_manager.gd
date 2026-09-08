class_name RaceManager
extends Node3D

## Composes one race and exclusively owns the Phase 5 state transitions.
## Lap, position, respawn, collision, countdown, and results logic stay in
## their dedicated child nodes (spec §6.1 rule 2 and §14).

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const DEFAULT_TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const DEFAULT_KART: KartData = preload("res://data/karts/medium.tres")
const DEFAULT_AI_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const DEFAULT_LAPS: int = 3
const DEFAULT_KART_COUNT: int = 8
const FINISHED_SPEED_RATIO: float = 0.5

const LEGAL_TRANSITIONS: Dictionary = {
	RaceState.LOADING: [RaceState.COUNTDOWN],
	RaceState.COUNTDOWN: [RaceState.RACING, RaceState.PAUSED],
	RaceState.RACING: [RaceState.FINISHING, RaceState.PAUSED],
	RaceState.FINISHING: [RaceState.RESULTS],
	RaceState.RESULTS: [RaceState.LOADING],
	RaceState.PAUSED: [RaceState.COUNTDOWN, RaceState.RACING],
}

@export var tuning: RaceTuning = preload("res://data/tuning/race_default.tres")

@onready var _lap_tracker: LapTracker = $LapTracker
@onready var _position_tracker: PositionTracker = $PositionTracker
@onready var _respawn_system: RespawnSystem = $RespawnSystem
@onready var _collision_resolver: KartCollisionResolver = $KartCollisionResolver
@onready var _item_manager: ItemManager = $ItemManager
@onready var _countdown: Countdown = $Countdown
@onready var _race_results: RaceResults = $RaceResults
@onready var _karts_root: Node3D = $Karts
@onready var _camera: RaceCamera = $RaceCamera
@onready var _hud: RaceHud = $HUD
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _results_screen: ResultsScreen = $ResultsScreen

var _state: int = RaceState.LOADING
var _paused_from_state: int = RaceState.RACING
var _config: RaceConfig
var _player_provider_factory: Callable
var _track: TrackRoot
var _karts: Array[KartController] = []
var _player_kart: KartController
var _ai_controllers: Dictionary[int, AIController] = {}
var _ai_context: AIRaceContext
var _finishing_elapsed: float = 0.0
var _results_delay_remaining: float = -1.0
var _final_entries: Array[RaceResults.Entry] = []


func _ready() -> void:
	if _config == null:
		_config = GameState.pending_race_config
	if _config == null:
		_config = _make_default_config()
	_begin_loading(false)


func _physics_process(delta: float) -> void:
	match _state:
		RaceState.COUNTDOWN:
			# Deferred so every kart's own _physics_process (which refreshes its
			# input snapshot) has already run this tick before Countdown samples
			# start input; RaceManager runs before its Karts children (spec §6.1).
			_advance_countdown.call_deferred(delta)
		RaceState.FINISHING:
			_advance_finishing(delta)


## Supplies a race config before entering the tree and an optional player
## provider factory `(KartController, RacingLine) -> InputProvider` for tests/sims.
func configure(config: RaceConfig, player_provider_factory: Callable = Callable()) -> void:
	_config = config
	_player_provider_factory = player_provider_factory


## Returns the current RaceState value.
func get_state() -> int:
	return _state


## Returns registered karts in grid-slot order.
func get_karts() -> Array[KartController]:
	return _karts.duplicate()


## Returns finalized result entries in rank order.
func get_results() -> Array[RaceResults.Entry]:
	return _final_entries.duplicate()


## Restarts the same config without replacing this manager instance.
func restart() -> void:
	get_tree().paused = false
	_begin_loading(true)


## Pauses the SceneTree only from COUNTDOWN or RACING.
func pause_race() -> void:
	if _state != RaceState.COUNTDOWN and _state != RaceState.RACING:
		return
	_paused_from_state = _state
	_transition_to(RaceState.PAUSED)
	get_tree().paused = true


## Restores the exact state from which the race was paused.
func resume_race() -> void:
	if _state != RaceState.PAUSED:
		return
	get_tree().paused = false
	_transition_to(_paused_from_state)


## Leaves the race through GameState's validated scene-change helper.
func back_to_menu() -> void:
	get_tree().paused = false
	GameState.change_scene("res://scenes/main.tscn")


## Returns whether a requested state edge belongs to the Phase 5 table.
static func can_transition(from_state: int, to_state: int) -> bool:
	var allowed: Array = LEGAL_TRANSITIONS.get(from_state, []) as Array
	return allowed.has(to_state)


## Returns whether FINISHING may close because everyone finished or time expired.
static func finishing_complete(finished_count: int, kart_count: int, elapsed: float, timeout: float) -> bool:
	return finished_count >= kart_count or elapsed >= timeout


func _begin_loading(is_restart: bool) -> void:
	if is_restart:
		_force_state(RaceState.LOADING)
	_clear_runtime()
	_validate_config()
	_track = _config.track.scene.instantiate() as TrackRoot
	_track.name = "Track"
	add_child(_track)
	move_child(_track, 0)
	_setup_systems()
	_spawn_karts()
	_register_track_elements()
	_race_results.setup(_config.track.id, _karts, _player_kart)
	_countdown.setup(tuning, _karts)
	_camera.set_target(_player_kart)
	_hud.bind(_player_kart, _lap_tracker, _position_tracker, _karts.size(), _config.laps, _item_manager)
	_pause_menu.bind(self)
	_pause_menu.hide_menu()
	_results_screen.hide_results()
	_transition_to(RaceState.COUNTDOWN)
	_countdown.start()


func _validate_config() -> void:
	if _config.track == null or _config.track.scene == null:
		push_warning("RaceConfig track is invalid; using track_01")
		_config.track = DEFAULT_TRACK
	_config.laps = maxi(1, _config.laps)
	_config.kart_count = clampi(_config.kart_count, 1, TrackRoot.MIN_GRID_SLOTS)
	if _config.player_slot >= 0:
		_config.player_slot = clampi(_config.player_slot, 0, _config.kart_count - 1)
	if _config.player_kart == null:
		_config.player_kart = DEFAULT_KART
	if _config.ai_difficulty == null:
		_config.ai_difficulty = DEFAULT_AI_DIFFICULTY


func _setup_systems() -> void:
	_lap_tracker.reset()
	_lap_tracker.total_laps = _config.laps
	_lap_tracker.setup(_track)
	_lap_tracker.set_race_active(false)
	_position_tracker.reset()
	_position_tracker.setup(_track, _lap_tracker)
	_position_tracker.set_update_hz(tuning.position_update_hz)
	_position_tracker.set_race_active(false)
	_respawn_system.clear_karts()
	_collision_resolver.clear_karts()
	_item_manager.reset()
	_item_manager.items_enabled = _config.items_enabled
	_item_manager.setup(_position_tracker, _track.get_racing_line(), _collision_resolver, _config.seed)
	_respawn_system.set_physics_process(false)
	_collision_resolver.set_physics_process(false)
	_item_manager.set_physics_process(false)
	if not _lap_tracker.kart_finished.is_connected(_on_kart_finished):
		_lap_tracker.kart_finished.connect(_on_kart_finished)


func _spawn_karts() -> void:
	var grid: Array[Transform3D] = _track.get_start_grid()
	_ai_controllers.clear()
	_ai_context = _make_ai_context()
	var race_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	race_rng.seed = _config.seed
	var ai_count: int = _config.kart_count - (1 if _config.player_slot >= 0 else 0)
	var ai_index: int = 0
	for slot: int in range(_config.kart_count):
		var kart: KartController = KART_SCENE.instantiate() as KartController
		var is_player: bool = slot == _config.player_slot
		kart.name = "PlayerKart" if is_player else "AiKart%d" % (slot + 1)
		kart.kart_data = _config.player_kart.duplicate(true) as KartData
		_karts_root.add_child(kart)
		kart.global_transform = grid[slot]
		kart.reset_motion_arcade()
		if is_player:
			kart.set_input_provider(_make_player_provider(kart))
			_player_kart = kart
		else:
			_spawn_ai_kart(kart, race_rng, ai_index, ai_count)
			ai_index += 1
		_karts.append(kart)
		_lap_tracker.register_kart(kart)
		_position_tracker.register_kart(kart)
		_collision_resolver.register_kart(kart)
		_item_manager.register_kart(kart)
		_respawn_system.register_kart(kart, _get_respawn_transform)
	_ai_context.player_kart = _player_kart


func _make_ai_context() -> AIRaceContext:
	var context: AIRaceContext = AIRaceContext.new()
	context.racing_line = _track.get_racing_line()
	context.track = _track
	context.position_tracker = _position_tracker
	context.item_manager = _item_manager
	context.request_respawn = _respawn_system.request_respawn
	context.get_countdown_phase_seconds = _countdown.get_phase_seconds
	return context


## Adds an `AIController` child driven by `RaceConfig.ai_difficulty`, staggering
## each kart's AI tick by a fraction of the tick period (spec §26).
func _spawn_ai_kart(kart: KartController, race_rng: RandomNumberGenerator, ai_index: int, ai_count: int) -> void:
	var controller: AIController = AIController.new()
	controller.name = "AIController"
	kart.add_child(controller)
	var kart_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	kart_rng.seed = race_rng.randi()
	var tick_interval: float = AIDifficulty.tick_interval(_config.ai_difficulty)
	var phase_offset: float = tick_interval * (float(ai_index) / maxf(float(ai_count), 1.0))
	controller.setup(kart, _track, _ai_context, _config.ai_difficulty, kart_rng, phase_offset)
	_ai_controllers[kart.get_instance_id()] = controller


func _make_player_provider(kart: KartController) -> InputProvider:
	if _player_provider_factory.is_valid():
		var candidate: Variant = _player_provider_factory.call(kart, _track.get_racing_line())
		if candidate is InputProvider:
			return candidate as InputProvider
		push_error("RaceManager player provider factory must return InputProvider")
	return PlayerInputProvider.new()


func _make_scripted_provider(kart: KartController, speed_ratio: float) -> ScriptedRaceInputProvider:
	var provider: ScriptedRaceInputProvider = ScriptedRaceInputProvider.new(kart, _track.get_racing_line(), speed_ratio)
	provider.set_drift_on_corners(true)
	return provider


func _register_track_elements() -> void:
	var kill_zones: Node = _track.get_node_or_null("KillZones")
	if kill_zones != null:
		for child: Node in kill_zones.get_children():
			if child is KillZone:
				_respawn_system.register_kill_zone(child as KillZone)
	var item_boxes: Node = _track.get_node_or_null("ItemBoxes")
	if item_boxes != null:
		for child: Node in item_boxes.get_children():
			if child is ItemBox:
				_item_manager.register_item_box(child as ItemBox)


func _on_kart_finished(kart: KartController, finish_time_seconds: float) -> void:
	EventBus.kart_finished.emit(kart, finish_time_seconds)
	var ai_controller: AIController = _ai_controllers.get(kart.get_instance_id()) as AIController
	if ai_controller != null:
		# AIDriver itself drops to safe-cruise mode once state == FINISHED
		# (spec §13.4), so keep feeding its own provider instead of swapping.
		kart.set_finished(ai_controller.get_input_provider())
	else:
		kart.set_finished(_make_scripted_provider(kart, FINISHED_SPEED_RATIO))
	# With a human participant, only their finish starts the FINISHING wind-down
	# (spec §14.1). Without one (RaceConfig.player_slot == -1, e.g. the sim),
	# there is no player finish to wait for, so the first kart to finish does.
	if (kart == _player_kart or _player_kart == null) and _state == RaceState.RACING:
		_transition_to(RaceState.FINISHING)


func _advance_countdown(delta: float) -> void:
	if _state != RaceState.COUNTDOWN:
		return
	if _countdown.advance(delta):
		_transition_to(RaceState.RACING)


func _advance_finishing(delta: float) -> void:
	_finishing_elapsed += delta
	if _results_delay_remaining < 0.0:
		if not finishing_complete(_finished_count(), _karts.size(), _finishing_elapsed, tuning.finish_timeout_seconds):
			return
		_results_delay_remaining = tuning.results_delay_seconds
	_results_delay_remaining = maxf(0.0, _results_delay_remaining - delta)
	if _results_delay_remaining <= 0.0:
		_finalize_results()


func _finalize_results() -> void:
	_position_tracker.force_update()
	var ranking: Array[KartController] = _position_tracker.get_ranking()
	var finish_times: Dictionary = {}
	for kart: KartController in _karts:
		if _lap_tracker.is_finished(kart):
			finish_times[kart.get_instance_id()] = _lap_tracker.get_finish_time(kart)
	_final_entries = _race_results.finalize(ranking, finish_times)
	_transition_to(RaceState.RESULTS)
	_results_screen.show_results(_final_entries, self)


func _finished_count() -> int:
	var count: int = 0
	for kart: KartController in _karts:
		if _lap_tracker.is_finished(kart):
			count += 1
	return count


func _get_respawn_transform(kart: KartController) -> Transform3D:
	return RespawnSystem.resolve_respawn_transform(kart, _lap_tracker, _track.get_racing_line(), _karts)


func _transition_to(new_state: int) -> void:
	if not can_transition(_state, new_state):
		push_error("Illegal race transition %d -> %d" % [_state, new_state])
		return
	var old_state: int = _state
	_force_state(new_state)
	_set_race_systems_active(new_state == RaceState.RACING or new_state == RaceState.FINISHING)
	if new_state == RaceState.PAUSED:
		_pause_menu.show_menu(self)
	else:
		_pause_menu.hide_menu()
	if new_state == RaceState.RACING and old_state == RaceState.COUNTDOWN:
		EventBus.race_started.emit()
	elif new_state == RaceState.FINISHING:
		_finishing_elapsed = 0.0
		_results_delay_remaining = -1.0


func _force_state(new_state: int) -> void:
	var old_state: int = _state
	_state = new_state
	if old_state != new_state:
		EventBus.race_state_changed.emit(old_state, new_state)


func _set_race_systems_active(active: bool) -> void:
	_lap_tracker.set_race_active(active)
	_position_tracker.set_race_active(active)
	_respawn_system.set_physics_process(active)
	_collision_resolver.set_physics_process(active)
	_item_manager.set_physics_process(active and _config.items_enabled)


func _clear_runtime() -> void:
	_final_entries.clear()
	_finishing_elapsed = 0.0
	_results_delay_remaining = -1.0
	_lap_tracker.reset()
	_position_tracker.reset()
	_respawn_system.clear_karts()
	_collision_resolver.clear_karts()
	_item_manager.reset()
	for kart: KartController in _karts:
		if is_instance_valid(kart):
			kart.free()
	_karts.clear()
	_ai_controllers.clear()
	_player_kart = null
	if is_instance_valid(_track):
		_track.free()
	_track = null


func _make_default_config() -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.track = DEFAULT_TRACK
	config.laps = DEFAULT_LAPS
	config.kart_count = DEFAULT_KART_COUNT
	config.player_kart = DEFAULT_KART
	return config

class_name RaceManager
extends Node3D
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const DEFAULT_TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const DEFAULT_KART: KartData = preload("res://data/karts/medium.tres")
const DEFAULT_LAPS: int = 3
const DEFAULT_KART_COUNT: int = 8
const MAX_KART_COUNT: int = 12
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
@onready var _audio: RaceAudio = $RaceAudio
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
@onready var _particle_budget: ParticleBudgetController = $ParticleBudgetController
@onready var _speed_lines: SpeedLines = $SpeedLines
@onready var _split_screen: SplitScreen = $SplitScreen
var _state: int = RaceState.LOADING
var _paused_from_state: int = RaceState.RACING
var _config: RaceConfig
var _player_provider_factory: Callable
var _track: TrackRoot
var _karts: Array[KartController] = []
var _player_kart: KartController
var _player_karts: Array[KartController] = []
var _player_indices: Dictionary[int, int] = {}
var _roster: RaceRoster
var _ai_controllers: Dictionary[int, AIController] = {}
var _ai_context: AIRaceContext
var _finishing_elapsed: float = 0.0
var _results_delay_remaining: float = -1.0
var _final_entries: Array[RaceResults.Entry] = []
var _hazard_relay: HazardRelay
var modes: RaceModes
var network: NetRace
var network_replica: bool = false
func _ready() -> void:
	network_replica = GameState.is_networked and not multiplayer.is_server()
	_hazard_relay = HazardRelay.new()
	modes = RaceModes.new()
	add_child(_hazard_relay)
	add_child(modes)
	if _config == null:
		_config = GameState.pending_race_config
	if _config == null:
		_config = _make_default_config()
	_begin_loading(false)
	if GameState.net_session != null:
		network = NetRace.new()
		add_child(network)
		network.configure(self, GameState.net_session)
func _physics_process(delta: float) -> void:
	if network_replica or (GameState.net_session != null and not GameState.net_session.running):
		return
	match _state:
		RaceState.COUNTDOWN:
			_advance_countdown.call_deferred(delta)
		RaceState.FINISHING:
			_advance_finishing(delta)
## Configures a race and optional `(KartController, RacingLine) -> InputProvider` factory.
func configure(config: RaceConfig, player_provider_factory: Callable = Callable()) -> void:
	_config = config
	_player_provider_factory = player_provider_factory
func get_state() -> int:
	return _state
func get_karts() -> Array[KartController]:
	return _karts.duplicate()
func get_human_karts() -> Array[KartController]:
	return _player_karts.duplicate()
func get_results() -> Array[RaceResults.Entry]:
	return _final_entries.duplicate()
func restart() -> void:
	if GameState.is_networked:
		back_to_menu()
		return
	get_tree().paused = false
	_begin_loading(true)
func pause_race() -> void:
	if GameState.is_networked:
		return
	if _state != RaceState.COUNTDOWN and _state != RaceState.RACING:
		return
	_paused_from_state = _state
	_transition_to(RaceState.PAUSED)
	get_tree().paused = true
func resume_race() -> void:
	if _state != RaceState.PAUSED:
		return
	get_tree().paused = false
	_transition_to(_paused_from_state)
func back_to_menu() -> void:
	if GameState.net_session != null:
		GameState.net_session.close()
	get_tree().paused = false
	GameState.change_scene("res://scenes/main.tscn")
func back_to_track_select() -> void:
	if GameState.is_networked:
		back_to_menu()
		return
	get_tree().paused = false
	GameState.change_scene("res://ui/menus/track_select.tscn")
static func can_transition(from_state: int, to_state: int) -> bool:
	var allowed: Array = LEGAL_TRANSITIONS.get(from_state, []) as Array
	return allowed.has(to_state)
static func finishing_complete(
	finished_count: int, kart_count: int, elapsed: float, timeout: float,
	finished_human_count: int = 1, human_count: int = 1,
) -> bool:
	if finished_count >= kart_count:
		return true
	return finished_human_count >= human_count and elapsed >= timeout
func _begin_loading(is_restart: bool) -> void:
	if is_restart:
		_force_state(RaceState.LOADING)
	_clear_runtime()
	RaceConfigBuilder.normalize(_config)
	_track = _config.track.scene.instantiate() as TrackRoot
	_track.name = "Track"
	add_child(_track)
	move_child(_track, 0)
	_setup_systems()
	_spawn_karts()
	if not network_replica:
		_register_track_elements()
	_race_results.setup_players(_config.track.id, _karts, _player_karts)
	var local_players: Array[KartController] = _player_karts
	if GameState.net_session != null and GameState.net_session.local_slot() >= 0:
		local_players = [_karts[GameState.net_session.local_slot()]]
	_audio.configure(local_players[0] if not local_players.is_empty() else null, _config.laps, _config.track.bgm_id)
	_countdown.setup(tuning, _karts)
	var primary_hud: RaceHud = RacePresentation.configure(
		get_world_3d(), _config, _karts, local_players, _lap_tracker, _position_tracker,
		_item_manager, _track, _camera, _hud, _speed_lines, _split_screen, _particle_budget,
	)
	modes.setup(_config, _player_kart, _track, primary_hud)
	if GameState.is_networked and not multiplayer.is_server(): primary_hud.bind_network(GameState.net_session)
	_pause_menu.bind(
		self, _player_kart != null and not GameState.automation_mode and not GameState.is_networked,
		_config.player_device_ids(),
	)
	_pause_menu.hide_menu()
	_results_screen.hide_results()
	_transition_to(RaceState.COUNTDOWN)
	if not GameState.is_networked:
		_countdown.start()
	else:
		for kart: KartController in _karts:
			kart.set_frozen(true)
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
	var grid: Array[Transform3D] = _track.get_start_grid(_config.kart_count)
	_roster = RaceRoster.new()
	_ai_controllers.clear()
	_ai_context = _make_ai_context()
	var race_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	race_rng.seed = _config.seed
	var ai_count: int = _config.ai_count()
	var ai_index: int = 0
	for slot: int in range(_config.kart_count):
		var kart: KartController = KART_SCENE.instantiate() as KartController
		var player: PlayerSlot = _config.player_for_grid_slot(slot)
		var is_player: bool = player != null
		kart.network_replica = network_replica
		kart.name = _player_name(_player_karts.size()) if is_player else "AiKart%d" % (slot + 1)
		var driver: DriverData = _roster.driver_for_slot(_config, slot, player)
		var base_kart: KartData = _roster.kart_for_slot(_config, slot, player)
		kart.kart_data = RaceConfigBuilder.apply_driver_mods(base_kart, driver)
		kart.set_driver_data(driver)
		var kart_audio: KartAudio = kart.get_node("KartAudio") as KartAudio
		if is_player and (GameState.net_session == null or slot == GameState.net_session.local_slot()):
			var is_primary: bool = slot == GameState.net_session.local_slot() if GameState.net_session != null else _player_karts.is_empty()
			kart_audio.set_local_player_mix(1.0 if is_primary else KartAudio.SECONDARY_PLAYER_GAIN, is_primary)
		else:
			kart_audio.set_player_audio(false)
		_karts_root.add_child(kart)
		kart.global_transform = grid[slot]
		kart.reset_motion_arcade()
		if is_player:
			kart.set_input_provider(_make_player_provider(kart, player))
			_player_indices[kart.get_instance_id()] = _player_karts.size()
			_player_karts.append(kart)
			if _player_kart == null:
				_player_kart = kart
		else:
			if not network_replica:
				_spawn_ai_kart(kart, race_rng, ai_index, ai_count)
			ai_index += 1
		_karts.append(kart)
		_lap_tracker.register_kart(kart)
		_position_tracker.register_kart(kart)
		_collision_resolver.register_kart(kart)
		_item_manager.register_kart(kart)
		_respawn_system.register_kart(kart, _get_respawn_transform, GameState.is_networked and is_player and not network_replica)
	_ai_context.player_kart = _player_kart
func _player_name(player_index: int) -> String:
	return "PlayerKart" if _config.human_count() == 1 else "PlayerKart%d" % (player_index + 1)
func _make_ai_context() -> AIRaceContext:
	var context: AIRaceContext = AIRaceContext.new()
	context.racing_line = _track.get_racing_line()
	context.track = _track
	context.position_tracker = _position_tracker
	context.item_manager = _item_manager
	context.request_respawn = _respawn_system.request_respawn
	context.get_countdown_phase_seconds = _countdown.get_phase_seconds
	return context
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
func _make_player_provider(kart: KartController, player: PlayerSlot) -> InputProvider:
	if _player_provider_factory.is_valid():
		var candidate: Variant = _player_provider_factory.call(kart, _track.get_racing_line())
		if candidate is InputProvider:
			return candidate as InputProvider
		push_error("RaceManager player provider factory must return InputProvider")
	return PlayerInputProvider.new(player.device_id)
func _register_track_elements() -> void:
	for hazard: Node in _track.get_node("Hazards").get_children():
		if hazard is Hazard:
			_hazard_relay.register_hazard(hazard as Hazard)
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
	if kart == _player_kart:
		modes.player_finished()
	EventBus.kart_finished.emit(kart, finish_time_seconds)
	var ai_controller: AIController = _ai_controllers.get(kart.get_instance_id()) as AIController
	if ai_controller != null:
		kart.set_finished(ai_controller.get_input_provider())
	else:
		kart.set_finished(ScriptedRaceInputProvider.new(kart, _track.get_racing_line(), FINISHED_SPEED_RATIO))
	if (_player_indices.has(kart.get_instance_id()) or _player_kart == null) and _state == RaceState.RACING:
		_transition_to(RaceState.FINISHING)
func _advance_countdown(delta: float) -> void:
	if _state != RaceState.COUNTDOWN:
		return
	if _countdown.advance(delta):
		_transition_to(RaceState.RACING)
func _advance_finishing(delta: float) -> void:
	var finished_humans: int = RaceCompletion.count(_lap_tracker, _player_karts)
	if finished_humans < _player_karts.size():
		_finishing_elapsed = 0.0
		return
	_finishing_elapsed += delta
	if _results_delay_remaining < 0.0:
		if not finishing_complete(
			RaceCompletion.count(_lap_tracker, _karts), _karts.size(),
			_finishing_elapsed, tuning.finish_timeout_seconds,
			finished_humans, _player_karts.size(),
		):
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
	modes.finalize(_final_entries)
	_transition_to(RaceState.RESULTS)
	_results_screen.show_results(_final_entries, self)
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
	active = active and not network_replica
	_lap_tracker.set_race_active(active)
	_position_tracker.set_race_active(active)
	_respawn_system.set_physics_process(active)
	_collision_resolver.set_physics_process(active)
	_item_manager.set_physics_process(active and _config.items_enabled)
func _clear_runtime() -> void:
	_split_screen.clear_views()
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
	_player_karts.clear()
	_player_indices.clear()
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
## Updates a replica state without enabling authoritative systems.
func apply_network_state(value: int) -> void:
	if not network_replica or value == RaceState.RESULTS or _state == RaceState.RESULTS:
		return
	var previous: int = _state
	_force_state(value)
	if previous == RaceState.COUNTDOWN and value == RaceState.RACING:
		network.emit_countdown(0) # Filters late/duplicate ticks vs. a snapshot beating reliable delivery.
		EventBus.race_started.emit()
func apply_network_results(entries: Array[RaceResults.Entry]) -> void:
	if not network_replica:
		return
	_final_entries = entries
	_force_state(RaceState.RESULTS)
	_results_screen.show_results(entries, self)

## Drops a departed human without resetting the surviving race services.
func remove_network_player(kart: KartController) -> void:
	for service: Node in [_lap_tracker, _position_tracker, _respawn_system, _collision_resolver, _item_manager, _countdown, _race_results]:
		service.unregister_kart(kart)
	_karts.erase(kart)
	_player_karts.erase(kart)
	_player_indices.erase(kart.get_instance_id())
	kart.set_input_provider(InputProvider.new())
	kart.free()
	if _state == RaceState.RACING and RaceCompletion.count(_lap_tracker, _player_karts) == _player_karts.size():
		_transition_to(RaceState.FINISHING)

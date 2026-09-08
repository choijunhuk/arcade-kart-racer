extends Node3D

## Phase 2 driving sandbox: swaps tracks and weight classes, spawns bump-test
## dummies, and composes collision/respawn systems without moving those
## responsibilities into KartController.

const RESET_KEY: Key = KEY_R
const TRACK_KEY: Key = KEY_T
const DUMMY_KEY: Key = KEY_B
const DUMMY_COUNT: int = 3
const DUMMY_START_DISTANCE: float = 4.0
const DUMMY_SPACING: float = 3.0
const DUMMY_LATERAL_OFFSET: float = 1.8
const TRACK_SCENES: Array[PackedScene] = [
	preload("res://track/tracks/test_loop/test_loop.tscn"),
	preload("res://track/tracks/test_loop_hills/test_loop_hills.tscn"),
	preload("res://track/tracks/test_hairpin/test_hairpin.tscn"),
	preload("res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"),
]
const TRACK_NODE_NAMES: Array[StringName] = [&"TestLoop", &"TestLoopHills", &"TestHairpin", &"Track01"]
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const KART_DATA: Array[KartData] = [
	preload("res://data/karts/light.tres"),
	preload("res://data/karts/medium.tres"),
	preload("res://data/karts/heavy.tres"),
]

@onready var _kart: KartController = $Kart
@onready var _camera: RaceCamera = $RaceCamera
@onready var _collision_resolver: KartCollisionResolver = $KartCollisionResolver
@onready var _respawn_system: RespawnSystem = $RespawnSystem
@onready var _lap_tracker: LapTracker = $LapTracker
@onready var _position_tracker: PositionTracker = $PositionTracker
@onready var _lap_label: Label = $HUD/LapLabel

const WATCH_NAMES: Array[StringName] = [
	&"speed", &"speed_ratio", &"state", &"grounded", &"lateral", &"terrain",
	&"slipstream", &"hit", &"invulnerable", &"air_time",
	&"drift_state", &"drift_charge", &"drift_tier", &"boost", &"trick_armed",
	&"lap", &"next_checkpoint", &"progress", &"wrong_way",
]
const SLIDER_NAMES: Array[StringName] = [
	&"max_speed", &"acceleration", &"base_turn_rate", &"grip", &"drag", &"brake_force", &"gravity", &"hover_height",
]

var _input_provider: PlayerInputProvider = PlayerInputProvider.new()
var _track: TrackRoot
var _track_index: int = 0
var _dummy_karts: Array[KartController] = []


func _ready() -> void:
	_track = $TestLoop as TrackRoot
	_kart.set_input_provider(_input_provider)
	_camera.set_target(_kart)
	_collision_resolver.register_kart(_kart)
	_configure_respawn_for_kart(_kart)
	_register_track_kill_zones()
	_setup_progress_for_track()
	_register_kart_progress(_kart)
	_register_track_item_boxes()
	_reset_to_grid()
	_register_debug_overlay()
	($HUD/DriftMeter as DriftMeter).set_controller(_kart.drift_controller)


func _process(_delta: float) -> void:
	_lap_label.text = "LAP %d/%d" % [mini(_lap_tracker.get_lap(_kart) + 1, _lap_tracker.total_laps), _lap_tracker.total_laps]


## Prevents DebugOverlay from calling stale watch/slider callables that
## capture this sandbox after it is freed (e.g. between test runs).
func _exit_tree() -> void:
	for watch_name: StringName in WATCH_NAMES:
		DebugOverlay.unwatch(watch_name)
	for slider_name: StringName in SLIDER_NAMES:
		DebugOverlay.remove_slider(slider_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			RESET_KEY:
				_reset_to_grid()
			TRACK_KEY:
				_switch_track()
			DUMMY_KEY:
				_spawn_dummy_karts()
			KEY_1:
				_swap_kart_data(0)
			KEY_2:
				_swap_kart_data(1)
			KEY_3:
				_swap_kart_data(2)
			KEY_4:
				_select_track(2)
			KEY_5:
				_select_track(3)
			_:
				return
		get_viewport().set_input_as_handled()


## Teleports the kart back to the first start-grid marker and clears momentum.
func _reset_to_grid() -> void:
	var grid_slot: Marker3D = _track.get_node("StartGrid/Grid01") as Marker3D
	_kart.global_transform = grid_slot.global_transform
	_kart.reset_motion_arcade()


func _switch_track() -> void:
	_select_track((_track_index + 1) % TRACK_SCENES.size())


func _select_track(index: int) -> void:
	_track_index = index
	remove_child(_track)
	_track.queue_free()
	_track = TRACK_SCENES[_track_index].instantiate() as TrackRoot
	_track.name = TRACK_NODE_NAMES[_track_index]
	add_child(_track)
	move_child(_track, 0)
	_register_track_kill_zones()
	_setup_progress_for_track()
	_register_kart_progress(_kart)
	for dummy: KartController in _dummy_karts:
		_register_kart_progress(dummy)
	_register_track_item_boxes()
	_configure_respawn_for_kart(_kart)
	for dummy: KartController in _dummy_karts:
		_configure_respawn_for_kart(dummy)
	_reset_to_grid()


func _swap_kart_data(index: int) -> void:
	var data: KartData = KART_DATA[index].duplicate(true) as KartData
	_kart.set_kart_data(data)


func _spawn_dummy_karts() -> void:
	_clear_dummy_karts()
	var forward: Vector3 = _kart.get_forward()
	var right: Vector3 = _kart.global_transform.basis.x
	for index: int in range(DUMMY_COUNT):
		var dummy: KartController = KART_SCENE.instantiate() as KartController
		dummy.name = "DummyKart%d" % (index + 1)
		dummy.kart_data = KART_DATA[index].duplicate(true) as KartData
		add_child(dummy)
		dummy.global_transform = _kart.global_transform
		dummy.global_position += forward * (DUMMY_START_DISTANCE + DUMMY_SPACING * index)
		if index % 2 == 1:
			dummy.global_position += right * DUMMY_LATERAL_OFFSET
		_dummy_karts.append(dummy)
		_collision_resolver.register_kart(dummy)
		_register_kart_progress(dummy)
		_configure_respawn_for_kart(dummy)


func _clear_dummy_karts() -> void:
	for dummy: KartController in _dummy_karts:
		_collision_resolver.unregister_kart(dummy)
		_respawn_system.unregister_kart(dummy)
		remove_child(dummy)
		dummy.queue_free()
	_dummy_karts.clear()


func _configure_respawn_for_kart(kart: KartController) -> void:
	_respawn_system.register_kart(kart, _get_respawn_transform)


func _register_track_kill_zones() -> void:
	var container: Node = _track.get_node("KillZones")
	for child: Node in container.get_children():
		if child is KillZone:
			_respawn_system.register_kill_zone(child as KillZone)


## Racing-line-oriented respawn (spec §14.5): the last checkpoint's
## RespawnPoint, stepping back along the line if another kart occupies it.
func _get_respawn_transform(kart: KartController) -> Transform3D:
	return RespawnSystem.resolve_respawn_transform(kart, _lap_tracker, _track.get_racing_line(), _all_karts())


func _all_karts() -> Array[KartController]:
	var karts: Array[KartController] = [_kart]
	karts.append_array(_dummy_karts)
	return karts


## (Re)binds LapTracker/PositionTracker to the current track. Call before
## registering any kart and again whenever `_track` changes.
func _setup_progress_for_track() -> void:
	_lap_tracker.setup(_track)
	_position_tracker.setup(_track, _lap_tracker)


func _register_kart_progress(kart: KartController) -> void:
	_lap_tracker.register_kart(kart)
	_position_tracker.register_kart(kart)


## Item effects are Phase 7 scope; this phase only relays the pickup signal.
func _register_track_item_boxes() -> void:
	var container: Node = _track.get_node_or_null("ItemBoxes")
	if container == null:
		return
	for child: Node in container.get_children():
		if child is ItemBox and not (child as ItemBox).collected.is_connected(_on_item_box_collected):
			(child as ItemBox).collected.connect(_on_item_box_collected)


func _on_item_box_collected(_body: Node3D) -> void:
	print("item box collected")


func _register_debug_overlay() -> void:
	DebugOverlay.watch(&"speed", func() -> String: return "%.1f" % _kart.get_speed())
	DebugOverlay.watch(&"speed_ratio", func() -> String: return "%.2f" % _kart.get_speed_ratio())
	DebugOverlay.watch(&"state", func() -> String: return _state_name(_kart.get_state()))
	DebugOverlay.watch(&"grounded", func() -> bool: return _kart.is_grounded())
	DebugOverlay.watch(&"lateral", func() -> String: return "%.2f" % _kart.get_lateral_speed())
	DebugOverlay.watch(&"terrain", func() -> StringName: return _kart.get_terrain_id())
	DebugOverlay.watch(&"slipstream", func() -> bool: return _kart.is_slipstream_active())
	DebugOverlay.watch(&"hit", func() -> String: return _hit_name(_kart.get_hit_state()))
	DebugOverlay.watch(&"invulnerable", func() -> bool: return _kart.is_invulnerable())
	DebugOverlay.watch(&"air_time", func() -> String: return "%.2f" % _kart.get_air_time())
	DebugOverlay.watch(&"drift_state", func() -> int: return _kart.get_drift_state())
	DebugOverlay.watch(&"drift_charge", func() -> String: return "%.2f" % _kart.get_drift_charge())
	DebugOverlay.watch(&"drift_tier", func() -> int: return _kart.get_drift_tier())
	DebugOverlay.watch(&"boost", func() -> String: return "%s %.2f" % [_kart.get_boost_source(), _kart.get_boost_remaining()])
	DebugOverlay.watch(&"trick_armed", func() -> bool: return _kart.is_trick_armed())
	DebugOverlay.watch(&"lap", func() -> int: return _lap_tracker.get_lap(_kart))
	DebugOverlay.watch(&"next_checkpoint", func() -> int: return _lap_tracker.get_next_checkpoint_index(_kart))
	DebugOverlay.watch(&"progress", func() -> String: return "%.1f" % _position_tracker.get_progress(_kart))
	DebugOverlay.watch(&"wrong_way", func() -> bool: return _lap_tracker.is_wrong_way(_kart))

	DebugOverlay.add_slider(&"max_speed", 5.0, 60.0,
		func() -> float: return _kart.kart_data.max_speed,
		func(value: float) -> void: _kart.kart_data.max_speed = value,
	)
	DebugOverlay.add_slider(&"acceleration", 1.0, 40.0,
		func() -> float: return _kart.kart_data.acceleration,
		func(value: float) -> void: _kart.kart_data.acceleration = value,
	)
	DebugOverlay.add_slider(&"base_turn_rate", 0.5, 6.0,
		func() -> float: return _kart.tuning.base_turn_rate,
		func(value: float) -> void: _kart.tuning.base_turn_rate = value,
	)
	DebugOverlay.add_slider(&"grip", 1.0, 20.0,
		func() -> float: return _kart.tuning.grip,
		func(value: float) -> void: _kart.tuning.grip = value,
	)
	DebugOverlay.add_slider(&"drag", 0.5, 20.0,
		func() -> float: return _kart.tuning.drag,
		func(value: float) -> void: _kart.tuning.drag = value,
	)
	DebugOverlay.add_slider(&"brake_force", 2.0, 40.0,
		func() -> float: return _kart.tuning.brake_force,
		func(value: float) -> void: _kart.tuning.brake_force = value,
	)
	DebugOverlay.add_slider(&"gravity", 5.0, 40.0,
		func() -> float: return _kart.tuning.gravity,
		func(value: float) -> void: _kart.tuning.gravity = value,
	)
	DebugOverlay.add_slider(&"hover_height", 0.05, 1.0,
		func() -> float: return _kart.tuning.hover_height,
		func(value: float) -> void: _kart.tuning.hover_height = value,
	)


func _state_name(state: int) -> String:
	match state:
		KartState.GROUNDED:
			return "GROUNDED"
		KartState.DRIFTING:
			return "DRIFTING"
		KartState.AIRBORNE:
			return "AIRBORNE"
		KartState.HIT:
			return "HIT"
		KartState.RESPAWNING:
			return "RESPAWNING"
		KartState.FINISHED:
			return "FINISHED"
		KartState.FROZEN:
			return "FROZEN"
		_:
			return "UNKNOWN"
func _hit_name(hit_state: int) -> String:
	match hit_state:
		HitReactor.HitType.BUMP:
			return "BUMP"
		HitReactor.HitType.SPIN_OUT:
			return "SPIN_OUT"
		HitReactor.HitType.TUMBLE:
			return "TUMBLE"
		HitReactor.HitType.SQUASH:
			return "SQUASH"
		_:
			return "NONE"

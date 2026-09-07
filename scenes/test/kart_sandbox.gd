extends Node3D

## Phase 1 driving sandbox: wires a player-controlled `kart.tscn` instance to
## the test loop's first grid slot, a follow camera, and DebugOverlay
## watches/sliders for the §9.10 tuning parameters. `R` resets the kart to
## the grid so a spin-out or wall-stick never ends the play session.

const RESET_KEY: Key = KEY_R

@onready var _kart: KartController = $Kart
@onready var _track: Node3D = $TestLoop
@onready var _camera: RaceCamera = $RaceCamera

const WATCH_NAMES: Array[StringName] = [&"speed", &"speed_ratio", &"state", &"grounded", &"lateral"]
const SLIDER_NAMES: Array[StringName] = [
	&"max_speed", &"acceleration", &"base_turn_rate", &"grip", &"drag", &"brake_force", &"gravity", &"hover_height",
]

var _input_provider: PlayerInputProvider = PlayerInputProvider.new()


func _ready() -> void:
	_kart.set_input_provider(_input_provider)
	_camera.set_target(_kart)
	_reset_to_grid()
	_register_debug_overlay()


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
		if key_event.physical_keycode == RESET_KEY and key_event.pressed and not key_event.echo:
			_reset_to_grid()
			get_viewport().set_input_as_handled()


## Teleports the kart back to the first start-grid marker and clears momentum.
func _reset_to_grid() -> void:
	var grid_slot: Marker3D = _track.get_node("StartGrid/Grid01") as Marker3D
	_kart.global_transform = grid_slot.global_transform
	_kart.velocity = Vector3.ZERO


func _register_debug_overlay() -> void:
	DebugOverlay.watch(&"speed", func() -> String: return "%.1f" % _kart.get_speed())
	DebugOverlay.watch(&"speed_ratio", func() -> String: return "%.2f" % _kart.get_speed_ratio())
	DebugOverlay.watch(&"state", func() -> String: return _state_name(_kart.get_state()))
	DebugOverlay.watch(&"grounded", func() -> bool: return _kart.is_grounded())
	DebugOverlay.watch(&"lateral", func() -> String: return "%.2f" % _estimate_lateral_speed())

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


## Sandbox-only readout; mirrors `KartVisuals`' estimate since lateral slip is
## not part of `KartController`'s public read-only API (spec §8).
func _estimate_lateral_speed() -> float:
	var forward: Vector3 = _kart.get_forward()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length() < 0.001:
		return 0.0
	return _kart.get_velocity().dot(right.normalized())

class_name KartController
extends CharacterBody3D

## Coordinates kart child components and exposes a read-only state API to
## camera/HUD/AI. Never reads the `Input` singleton directly (spec §23);
## drives from whatever `InputProvider` is installed. Spec: §8, §9.3.

signal state_changed(old_state: int, new_state: int)

@export var kart_data: KartData = preload("res://data/karts/medium.tres")
@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")

@onready var _physics: KartPhysics = $KartPhysics
@onready var _ground_rays: Node3D = $GroundRays
@onready var _terrain_sensor: TerrainSensor = $TerrainSensor
@onready var _terrain_probe: Area3D = $TerrainProbe
@onready var _slipstream_sensor: SlipstreamSensor = $SlipstreamSensor
@onready var _slipstream_cast: ShapeCast3D = $SlipstreamSensor/ShapeCast3D
@onready var _hit_reactor: HitReactor = $HitReactor

var input_provider: InputProvider = InputProvider.new()
var state: int = KartState.GROUNDED
var _current_terrain_id: StringName = &"asphalt"
var _slipstream_active: bool = false
var _respawning: bool = false
var _ungrounded_ticks: int = 0
var _throttle_held: bool = false


func _ready() -> void:
	var rays: Array[RayCast3D] = []
	for child: Node in _ground_rays.get_children():
		if child is RayCast3D:
			rays.append(child as RayCast3D)
	_physics.setup(self, rays, tuning, kart_data)
	_terrain_sensor.setup(_terrain_probe, rays, kart_data)
	_slipstream_sensor.setup(_slipstream_cast, self, tuning)
	_hit_reactor.setup(self, _physics, tuning)
	_physics.wall_head_on.connect(_on_wall_head_on)


func _physics_process(delta: float) -> void:
	var frame: InputFrame = _get_input_frame()
	var terrain: KartPhysics.TerrainSample = _sample_terrain()
	var ground: KartPhysics.GroundProbe = _physics.probe_ground()
	var drift_result: KartPhysics.DriftResult = _update_drift(frame, ground)
	var boost_result: KartPhysics.BoostResult = _update_boost(delta)
	_physics.integrate(frame, terrain, ground, drift_result, boost_result, delta)
	_update_hit_reactor(delta)
	_update_state(ground)


## Installs a new input source. Karts never read `Input` directly (spec §23).
func set_input_provider(provider: InputProvider) -> void:
	input_provider = provider


func get_speed() -> float:
	return _physics.speed


## Returns the local sideways velocity component used by arcade grip.
func get_lateral_speed() -> float:
	return _physics.lateral


## Returns seconds spent continuously without enough grounded rays.
func get_air_time() -> float:
	return _physics.air_time


## Returns KartData's mass scalar for deterministic kart contact.
func get_mass() -> float:
	return kart_data.weight


## Returns whether HitReactor currently rejects new hit effects.
func is_invulnerable() -> bool:
	return _hit_reactor.is_invulnerable()


## Returns the most recently sampled TerrainData identifier.
func get_terrain_id() -> StringName:
	return _current_terrain_id


## Returns whether a fully charged slipstream is being sustained.
func is_slipstream_active() -> bool:
	return _slipstream_active


## Returns the active hit type, or -1 while no hit reaction is running.
func get_hit_state() -> int:
	return _hit_reactor.get_hit_type() if _hit_reactor.is_active() else -1


## Returns normalized elapsed hit progress for visual-only deformation.
func get_hit_progress() -> float:
	return _hit_reactor.get_progress()


## Returns whether the raw provider held throttle on the latest physics tick.
func is_throttle_held() -> bool:
	return _throttle_held


func get_speed_ratio() -> float:
	return clampf(absf(_physics.speed) / maxf(kart_data.max_speed, 0.001), 0.0, 1.0)


func get_forward() -> Vector3:
	return -global_transform.basis.z


func is_grounded() -> bool:
	return _physics.grounded


func get_ground_normal() -> Vector3:
	return _physics.ground_normal


func get_state() -> int:
	return state


func get_kart_data() -> KartData:
	return kart_data


## Rebinds KartData for sandbox weight-class comparisons.
func set_kart_data(data: KartData) -> void:
	kart_data = data
	_physics.set_kart_data(data)
	_terrain_sensor.set_kart_data(data)


## Converts a world velocity change into local speed/lateral components.
func apply_impulse_arcade(delta_velocity: Vector3, yaw_nudge: float) -> void:
	_physics.apply_world_delta_velocity(delta_velocity)
	rotate(Vector3.UP, yaw_nudge)


## Applies an external hit through the invulnerability gate.
func apply_hit(type: HitReactor.HitType, source: Node = null) -> bool:
	return _hit_reactor.apply(type, source)


## Starts the tick-driven respawn state and suppresses driving input.
func begin_respawn() -> void:
	_respawning = true
	_set_state(KartState.RESPAWNING)


## Teleports to a safe transform, clears momentum, and grants protection.
func teleport_for_respawn(target: Transform3D) -> void:
	global_transform = target
	_physics.reset_motion()
	_hit_reactor.grant_invulnerability(tuning.respawn_invulnerability_duration)


## Clears momentum without changing state or granting invulnerability.
func reset_motion_arcade() -> void:
	_physics.reset_motion()


## Ends respawn freeze and returns state control to ground probing.
func finish_respawn() -> void:
	_respawning = false
	_ungrounded_ticks = 0
	_set_state(KartState.GROUNDED)


## Step 1 (§9.3): HIT/RESPAWNING/FROZEN states drive with a zero frame. The
## provider is still polled so edge-detected inputs (drift/item press) do not
## desynchronize once HitReactor/RespawnSystem/Countdown exist in later phases.
func _get_input_frame() -> InputFrame:
	var frame: InputFrame = input_provider.get_frame()
	_throttle_held = frame.throttle > 0.0
	if state == KartState.HIT or state == KartState.RESPAWNING or state == KartState.FROZEN:
		return InputFrame.zero()
	return frame


func _sample_terrain() -> KartPhysics.TerrainSample:
	var sample: KartPhysics.TerrainSample = _terrain_sensor.sample()
	_current_terrain_id = sample.terrain_id
	return sample


## TODO(phase-3): DriftController is not implemented yet; drifting never
## engages and no visual angle or grip override is produced.
func _update_drift(_frame: InputFrame, _ground: KartPhysics.GroundProbe) -> KartPhysics.DriftResult:
	return KartPhysics.DriftResult.new()


## TODO(phase-3): route slipstream exit through BoostController once it owns
## boost stacking. Phase 2 keeps the timed multiplier in BoostResult.
func _update_boost(delta: float) -> KartPhysics.BoostResult:
	var timer: SlipstreamSensor.TimerResult = _slipstream_sensor.tick(delta)
	var result: KartPhysics.BoostResult = KartPhysics.BoostResult.new()
	result.speed_mult = timer.speed_mult
	result.accel_mult = timer.speed_mult
	_slipstream_active = timer.active
	return result


func _update_hit_reactor(delta: float) -> void:
	_hit_reactor.tick(delta)


func _update_state(ground: KartPhysics.GroundProbe) -> void:
	if _respawning:
		_set_state(KartState.RESPAWNING)
		return
	if _hit_reactor.is_active():
		_set_state(KartState.HIT)
		return
	if ground.grounded:
		_ungrounded_ticks = 0
		_set_state(KartState.GROUNDED)
		return
	_ungrounded_ticks += 1
	if _ungrounded_ticks > tuning.airborne_grace_ticks:
		_set_state(KartState.AIRBORNE)


func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old_state: int = state
	state = new_state
	state_changed.emit(old_state, new_state)


func _on_wall_head_on() -> void:
	_hit_reactor.apply(HitReactor.HitType.BUMP, self)

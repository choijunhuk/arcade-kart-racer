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

var input_provider: InputProvider = InputProvider.new()
var state: int = KartState.GROUNDED


func _ready() -> void:
	var rays: Array[RayCast3D] = []
	for child: Node in _ground_rays.get_children():
		if child is RayCast3D:
			rays.append(child as RayCast3D)
	_physics.setup(self, rays, tuning, kart_data)


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


## Step 1 (§9.3): HIT/RESPAWNING/FROZEN states drive with a zero frame. The
## provider is still polled so edge-detected inputs (drift/item press) do not
## desynchronize once HitReactor/RespawnSystem/Countdown exist in later phases.
func _get_input_frame() -> InputFrame:
	var frame: InputFrame = input_provider.get_frame()
	if state == KartState.HIT or state == KartState.RESPAWNING or state == KartState.FROZEN:
		return InputFrame.zero()
	return frame


## TODO(phase-2): TerrainSensor is not implemented yet; every surface behaves
## like neutral asphalt until it exists.
func _sample_terrain() -> KartPhysics.TerrainSample:
	return KartPhysics.TerrainSample.new()


## TODO(phase-3): DriftController is not implemented yet; drifting never
## engages and no visual angle or grip override is produced.
func _update_drift(_frame: InputFrame, _ground: KartPhysics.GroundProbe) -> KartPhysics.DriftResult:
	return KartPhysics.DriftResult.new()


## TODO(phase-3): BoostController is not implemented yet; no boost source can
## multiply speed or acceleration.
func _update_boost(_delta: float) -> KartPhysics.BoostResult:
	return KartPhysics.BoostResult.new()


## TODO(phase-2): HitReactor is not implemented yet; the kart can never enter
## the HIT state from a projectile or hazard.
func _update_hit_reactor(_delta: float) -> void:
	pass


func _update_state(ground: KartPhysics.GroundProbe) -> void:
	var new_state: int = KartState.GROUNDED if ground.grounded else KartState.AIRBORNE
	if new_state == state:
		return
	var old_state: int = state
	state = new_state
	state_changed.emit(old_state, new_state)
